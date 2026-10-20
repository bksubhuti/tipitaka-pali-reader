// ignore_for_file: constant_identifier_names

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/services/provider/script_language_provider.dart';
import 'package:tipitaka_pali/utils/font_utils.dart';
import 'package:tipitaka_pali/utils/pali_script.dart';
import 'package:tipitaka_pali/utils/pali_script_converter.dart';
import 'package:tipitaka_pali/utils/script_detector.dart';

import '../../../../business_logic/models/definition.dart';
import '../../../../business_logic/models/dictionary_history.dart';
import '../../../../services/database/database_helper.dart';
import '../../../../services/database/dictionary_service.dart';
import '../../../../services/repositories/dictionary_history_repo.dart';
import '../../../../services/repositories/dictionary_repo.dart';
import 'dictionary_state.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';

// global variable
final ValueNotifier<String?> globalLookupWord = ValueNotifier<String?>(null);
DateTime? _lookupAskedAt;

/// Asks the dictionary to look up [word].
///
/// Asked for twice, the same word is looked up twice: a value notifier says
/// nothing when it is given the value it already holds, so a second tap on
/// a word whose lookup had been missed or had failed did nothing at all.
/// The time is kept so a dictionary built just after the tap still takes
/// the word; see [DictionaryController.onLoad].
void lookUpWord(String word) {
  _lookupAskedAt = DateTime.now();
  globalLookupWord.value = null;
  globalLookupWord.value = word;
}

enum DictAlgorithm { Auto, TPR, DPD }

extension ParseToString on DictAlgorithm {
  String toStr() {
    return toString().split('.').last;
  }
}

class DictionaryController with ChangeNotifier {
  final DictionaryHistoryRepository dictionaryHistoryRepository;
  final DictionaryRepository dictionaryRepository;

  String _currentlookupWord = '';
  String get lookupWord => _currentlookupWord;
  BuildContext context;

  DictionaryState _dictionaryState = const DictionaryState.initial();
  DictionaryState get dictionaryState => _dictionaryState;

  DictAlgorithm _currentAlgorithmMode = DictAlgorithm.Auto;
  DictAlgorithm get currentAlgorithmMode => _currentAlgorithmMode;

  // TextEditingController textEditingController = TextEditingController();

  final ValueNotifier<List<DictionaryHistory>> _histories =
      ValueNotifier<List<DictionaryHistory>>([]);
  ValueListenable<List<DictionaryHistory>> get histories => _histories;

  DictionaryController({
    required this.context,
    required this.dictionaryHistoryRepository,
    required this.dictionaryRepository,
    String? lookupWord,
  }) : _currentlookupWord = lookupWord ?? '';

  void onLoad() {
    debugPrint('init dictionary controller');
    globalLookupWord.addListener(_lookupWordListener);

    // load history
    dictionaryHistoryRepository.getAll().then((values) {
      values.sort((a, b) => a.dateTime.compareTo(b.dateTime));
      _histories.value = [...values];
    });

    // A word tapped while this dictionary was still being built. The reader
    // gives it a moment to start listening and then sets the word; when it
    // takes longer, the word was set before anyone listened, and the panel
    // stayed on its history as if nothing had been tapped. Only a word asked
    // for just now: opening the dictionary later still shows the history.
    final asked = _lookupAskedAt;
    final pending = globalLookupWord.value;
    if (_currentlookupWord.isEmpty &&
        pending != null &&
        pending.isNotEmpty &&
        asked != null &&
        DateTime.now().difference(asked) < const Duration(seconds: 3)) {
      _currentlookupWord = pending;
    }

    if (_currentlookupWord.isNotEmpty) {
      _lookupDefinition();
    }
  }

  /// Counts lookups, so an older one that finishes late does not replace
  /// the answer to a newer one.
  int _lookups = 0;

  @override
  void dispose() {
    debugPrint('dictionary Controller is disposed');
    globalLookupWord.removeListener(_lookupWordListener);
    super.dispose();
  }

  void _lookupWordListener() {
    if (globalLookupWord.value != null) {
      _currentlookupWord = globalLookupWord.value ?? '';
      debugPrint('lookup word: $_currentlookupWord');
      if (_currentlookupWord.isNotEmpty) {
        _lookupDefinition();
      }
    }
  }

  Future<void> _lookupDefinition() async {
    _dictionaryState = const DictionaryState.loading();
    notifyListeners();
    if (_currentlookupWord.isEmpty) {
      return;
    }
    final lookup = ++_lookups;
    // loading definitions
    String romanWord = _currentlookupWord;
    Script inputScript = ScriptDetector.getLanguage(romanWord);
    if (inputScript != Script.roman) {
      romanWord =
          PaliScript.getRomanScriptFrom(script: inputScript, text: romanWord);
    }

    // A lookup that throws, the database busy with an update for instance,
    // left the spinner turning for good. It says not found instead, and the
    // word can be tapped again.
    String definition;
    try {
      definition = await loadDefinition(romanWord);
    } catch (e) {
      debugPrint('dictionary lookup of $romanWord failed: $e');
      definition = '';
    }
    if (lookup != _lookups) return;
    debugPrint(
        '==================> $romanWord, is empty: ${definition.isEmpty}');
    if (definition.isEmpty) {
      _dictionaryState = const DictionaryState.noData();
      notifyListeners();
    } else {
      _dictionaryState = DictionaryState.data(definition);
      notifyListeners();
      // save to history
      // I'm removing the code to check if it is there already because
      // the insert function deletes and then re-adds it.. This will make the ording proper.
      //if (!isContainInHistories(_histories.value, romanWord)) {
      //TODO  remove this .. now done word click await dictionaryHistoryRepository.insert(romanWord);
      // refresh histories
      final histories = await dictionaryHistoryRepository.getAll();
      histories.sort((a, b) => a.dateTime.compareTo(b.dateTime));
      _histories.value = [...histories];
    }
    //} // is container in history
  }

  Future<String> loadDefinition(String word) async {
    Prefs.numberWordsLookedUp++;
    // use only if setting is good in prefs
    if (Prefs.saveClickToClipboard == true) {
      await Clipboard.setData(ClipboardData(text: word));
    }
    debugPrint('_currentAlgorithmMode: $_currentAlgorithmMode');

    switch (_currentAlgorithmMode) {
      case DictAlgorithm.Auto:
        return await searchAuto(word);
      case DictAlgorithm.TPR:
        return searchWithTPR(word);
      case DictAlgorithm.DPD:
        return searchWithDpdSplit(word);
    }
  }

  Future<String> searchAuto(String word) async {
    //
    // Audo mode will use TPR algorithm first
    // if defintion was found, will be display this definition
    // Otherwise will be display result of Dpd splitter a

    final before = DateTime.now();

    String definition = await searchWithTPR(word);
    // debugPrint(
    //     'TPR definition "$definition", definition.isEmpty: ${definition.isEmpty}');
    if (definition.isEmpty) definition = await searchWithDpdSplit(word);
    // debugPrint('DPR def: $definition');
    final after = DateTime.now();
    final differnt = after.difference(before);
    debugPrint('compute time: $differnt');

    return definition;
  }

  Future<String> searchWithTPR(String word) async {
    final originalWord = word;
    // looking up using estimated stem word
    final dictionaryProvider =
        DictionarySerice(DictionaryDatabaseRepository(DatabaseHelper()));
    // now get the headword all times.
    String dpdHeadWords = await dictionaryProvider.getDpdHeadwords(word);
    // if we find the word.. then we isAlreadyStem = true;
    // make the lookup word that new dpdHeadWord.

    bool isAlreadyStem = false;
    if (dpdHeadWords.isNotEmpty) {
      // TODO get list from ven Bodhirasa for exceptions Bhagavaa and bhikkhave etc.

      //List<String> dpdList = dpdHeadWords.split(RegExp(r"[, ]"));
      List<String> dpdList = dpdHeadWords.split(",");

      // remove the left bracket and single quotes      String dpdword = dpdList[0].replaceAll(RegExp(r"[\'\[\]]"), "");
      String dpdword = dpdList[0].replaceAll(RegExp(r"[\'\[\]\d\s]"), "");

//small case switch.. little hack.
      switch (dpdword) {
        case "āyasmant":
          word = "āyasmantu";
          break;
        case "bhikkhave":
          word = "bhikkhu";
          break;
        case "ambho":
          isAlreadyStem = true;
          break;
        default:
          if (word.contains("āyasm")) {
            dpdword = "āyasmantu";
          }

          // total hack for ending in vant change to vantu
          // works in most cases.
          if (dpdword.length > 4) {
            if (dpdword.substring(dpdword.length - 4, dpdword.length) ==
                "vant") {
              dpdword = "${dpdword.substring(0, dpdword.length - 4)}vantu";
            }
          }

          word = dpdword;
          break;
      }
    }

    final definitions = await dictionaryProvider.getDefinition(word,
        isAlreadyStem: isAlreadyStem);

    // check to see if dpd is used.
    // separate table and process for dpd
    if (Prefs.isDpdOn) {
      if (dpdHeadWords.isNotEmpty) {
        Definition dpdDefinition =
            await dictionaryProvider.getDpdDefinition(dpdHeadWords);
        if (Prefs.isDpdGrammarOn) {
          Definition grammarDef =
              await dictionaryProvider.getDpdGrammarDefinition(originalWord);
          if (grammarDef.word.isNotEmpty) {
            dpdDefinition.definition += grammarDef.definition;
          }
        }
        definitions.insert(0, dpdDefinition);
        definitions.sort((a, b) => a.userOrder.compareTo(b.userOrder));
      }
    }
    //if (definitions.isEmpty) return '';
    //if (definitions[0].definition.isEmpty) return '';
    String finalDef = _formatDefinitions(definitions);
    if (Prefs.alwaysShowDpdSplitter) {
      finalDef += await getWordSplitAsDefString(originalWord);
    }
    return finalDef;
  }

  Future<String> searchWithDpdSplit(String word) async {
    // looking up using dpd word split
    List<Definition> definitions = [];
    final dictionaryProvider =
        DictionarySerice(DictionaryDatabaseRepository(DatabaseHelper()));
    // frist dpr_stem will be used for stem
    // stem is single word mostly
    final String dprStem = await dictionaryProvider.getDprStem(word);
    if (dprStem.isNotEmpty) {
      definitions =
          await dictionaryProvider.getDefinition(dprStem, isAlreadyStem: true);
    }

    debugPrint('dprStem: $dprStem');
    debugPrint('Prefs.isDpdOn: ${Prefs.isDpdOn}');
    debugPrint('definitions: $definitions');

    if (Prefs.isDpdOn) {
      String dpdHeadWord = await dictionaryProvider.getDpdHeadwords(word);
      debugPrint('dpdHeadWord: $dpdHeadWord for "$word"');

      if (dpdHeadWord.isNotEmpty) {
        Definition dpdDefinition =
            await dictionaryProvider.getDpdDefinition(dpdHeadWord);
        definitions.insert(0, dpdDefinition);
      }

      if (definitions.isNotEmpty) {
        definitions.sort((a, b) => a.userOrder.compareTo(b.userOrder));
        return _formatDefinitions(definitions);
      }
    }

    // not found in dpr_stem
    // will be lookup in dpd_word_split
    // breakup is multi-words
    return await getWordSplitAsDefString(word);
  }

  Future<void> onLookup(String word) async {
    _currentlookupWord = word;
    _lookupDefinition();
  }

  void onInputIsEmpty() {
    _currentlookupWord = '';
    _dictionaryState = const DictionaryState.initial();
    notifyListeners();
  }

  Future<List<String>> getSuggestions(String word) async {
    return DictionarySerice(DictionaryDatabaseRepository(DatabaseHelper()))
        .getSuggestions(word);
  }

  String _formatDefinitions(List<Definition> definitions) {
    String formattedDefinition = '';
    for (Definition definition in definitions) {
      // Get the font for the current dictionary book name
      String? fontName = getDictionaryFont(definition.bookName);

      // If a specific font is returned, use it in the styling
      String fontStyling = fontName != null ? 'font-family: $fontName;' : '';

      // Apply font styling to the book name and definition content
      formattedDefinition += _addStyleToBook(definition.bookName, fontStyling);

      String def = definition.definition;
      formattedDefinition += '<div style="$fontStyling">$def</div>';
    }
    return formattedDefinition;
  }

  String _addStyleToBook(String book, String? additionalStyling) {
    String bkColor =
        Theme.of(context).primaryColor.value.toRadixString(16).substring(2);
    String foreColor =
        Theme.of(context).canvasColor.value.toRadixString(16).substring(2);

    String combinedStyles =
        'background-color: #$bkColor; color: #$foreColor; text-align:center; padding-bottom:5px; padding-top: 5px;';
    if (additionalStyling != null && additionalStyling.isNotEmpty) {
      combinedStyles += ' $additionalStyling';
    }

    return '<h3 style="$combinedStyles">$book</h3>\n<br>\n';
  }

  List<String> getWordsFrom({required String breakup}) {
    // the dprBreakup data look like this:
    // 'bhikkhu':'bhikkhu (bhikkhu)',
    //
    // or this:
    // 'āyasmā':'āyasmā (āya, āyasmant, āyasmanta)',
    //
    // or this:
    // 'asaṃkiliṭṭhaasaṃkilesiko':'asaṃ-kiliṭṭhā-saṃkilesiko (asa, asā, kiliṭṭha, saṃkilesiko)',
    //
    // - The key of the dprBreakup object is the word being look up here (the "key" parameter of this function)
    // - The format of the break up is as follows:
    //   - the original word broken up with dashes (-) and the components of the breakup as dictionary entries in ()
    //
    /*
    final indexOfLeftBracket = breakup.indexOf(' (');
    final indexOfRightBracket = breakup.indexOf(')');
    var breakupWords = breakup
        .substring(indexOfLeftBracket + 2, indexOfRightBracket)
        .split(', ');
    // cleans up DPR-specific stuff
    breakupWords =
        breakupWords.map((word) => word.replaceAll('`', '')).toList();
        */

    return breakup.split(",");
  }

  void onModeChanged(DictAlgorithm? value) {
    if (value != null) {
      _currentAlgorithmMode = value;
      _lookupDefinition();
    }
  }

  void onWordClicked(String word) async {
    word = _removeNonCharacter(word);

    word = word.toLowerCase();
    _currentlookupWord = word;

    _lookupDefinition();
  }

  void onClickedNext() {
    if (_histories.value.isEmpty) {
      return;
    }
    final index = _getIndex(_histories.value, _currentlookupWord);
    if (index == -1) {
      return;
    }

    if (index + 1 < _histories.value.length) {
      _currentlookupWord = _histories.value[index + 1].word;
      _lookupDefinition();
    }
  }

  void onClickedPrevious() {
    if (_histories.value.isEmpty) {
      return;
    }
    final index = _getIndex(_histories.value, _currentlookupWord);
    if (index == _histories.value.length) {
      return;
    }

    if (index > 0) {
      _currentlookupWord = _histories.value[index - 1].word;
      _lookupDefinition();
    }
  }

  Future<void> onDelete(String word) async {
    await dictionaryHistoryRepository.delete(word);
    final histories = await dictionaryHistoryRepository.getAll();
    histories.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    _histories.value = [...histories];
    _dictionaryState = const DictionaryState.initial();
  }

  String _removeNonCharacter(String input) {
    final re = RegExp(r'[^a-zāīūṅñṭḍṇḷṃ ]+', caseSensitive: false);
    final clean = input.replaceAll(re, '');
    return clean;
  }

  int _getIndex(List<DictionaryHistory> histories, String word) {
    if (histories.isEmpty) return -1;
    // histories.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    for (int i = 0; i < histories.length; i++) {
      if (histories[i].word == word) {
        return i;
      }
    }
    // not found
    return -1;
  }

  bool isContainInHistories(List<DictionaryHistory> histories, String word) {
    if (histories.isEmpty) return false;
    // histories.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    for (int i = 0; i < histories.length; i++) {
      if (histories[i].word == word) {
        return true;
      }
    }
    // not found
    return false;
  }

  void onClickedHistoryButton() {
    _currentlookupWord = '';
    _dictionaryState = const DictionaryState.initial();
    notifyListeners();
  }

  String replaceQuotesWithRegex(String input) {
    // Check if the input is not null or empty
    if (input.isNotEmpty) {
      // Define a regex pattern that matches the first and last quotes in the input
      RegExp pattern = RegExp(r'^"|"$');
      // Replace all matches of the pattern with empty strings
      String output = input.replaceAll(pattern, '');
      // Return the output
      return output;
    } else {
      // Return an empty string if the input is null or empty
      return '';
    }
  }

  Future<String> getWordSplitAsDefString(word) async {
    final dictionaryProvider =
        DictionarySerice(DictionaryDatabaseRepository(DatabaseHelper()));

    final String breakupText = await dictionaryProvider.getDpdWordSplit(word);

    if (breakupText.isEmpty) return '';

    final List<String> words = getWordsFrom(breakup: breakupText);

    // Get the current script from the ScriptLanguageProvider
    final currentScript = context.read<ScriptLanguageProvider>().currentScript;

    // Get the font name for the current script
    String? fontName = FontUtils.getfontName(script: currentScript);
    String fontStyling = 'font-family: $fontName;';

    // Formating header with the appropriate font
    String formattedDefinition =
        _addStyleToBook(AppLocalizations.of(context)!.wordSplit, fontStyling);

    formattedDefinition +=
        '<p class="definition" style="$fontStyling"> <b>${PaliScript.getScriptOf(
      romanText: word,
      script: currentScript,
    )}</b> <br>';
    for (String breakup in words) {
      if (currentScript == Script.roman) {
        breakup;
      } else {
        breakup = PaliScript.getScriptOf(
          romanText: breakup,
          script: currentScript,
        );
      }

      formattedDefinition += "<br>" + breakup + '<br>';
    }
    formattedDefinition += '</p>';
    return formattedDefinition;
  }

  String? getDictionaryFont(String dictionaryBookName) {
    switch (dictionaryBookName) {
      case "ဦးဟုတ်စိန် ပါဠိ-မြန်မာအဘိဓာန်":
        return FontUtils.getfontName(
            script: Script.myanmar); // Replace with actual font name
      case "ပါဠိဓာတ်အဘိဓာန်":
        return FontUtils.getfontName(
            script: Script.myanmar); // Replace with actual font name
      case "ဓာတွတ္ထပန်းကုံး":
        return FontUtils.getfontName(
            script: Script.myanmar); // Replace with actual font name
      case "တိပိဋက ပါဠိ-မြန်မာ အဘိဓာန်":
        return FontUtils.getfontName(
            script: Script.myanmar); // Replace with actual font name
      case "Sinhala 2":
        return FontUtils.getfontName(
            script: Script.sinhala); // Replace with actual font name
      case "Sinhala 1":
        return FontUtils.getfontName(
            script: Script.sinhala); // Replace with actual font name
      case "Pali Proper Names (DPPN)":
        return FontUtils.getfontName(
            script: Script.roman); // Replace with actual font name
      case "Pali English Ultimate (PEU)":
        return FontUtils.getfontName(
            script: Script.roman); // Replace with actual font name
      case "PEA Algo Used":
        return FontUtils.getfontName(
            script: Script.roman); // Replace with actual font name
      case "PTS Pali-English Dictionary":
        return FontUtils.getfontName(
            script: Script.roman); // Replace with actual font name
      case "Digital Pāḷi Dictionary":
        return FontUtils.getfontName(
            script: Script.roman); // Replace with actual font name
      case "Concise Pali-English Dictionary":
        return FontUtils.getfontName(
            script: Script.roman); // Replace with actual font name
      default:
        return null; // Default font if none of the cases match
    }
  }

  getDpdInflection(int wordId) {
    final dictionaryProvider =
        DictionarySerice(DictionaryDatabaseRepository(DatabaseHelper()));
    return dictionaryProvider.getDpdInflection(wordId);
  }

  getDpdRootFamily(int wordId) {
    final dictionaryProvider =
        DictionarySerice(DictionaryDatabaseRepository(DatabaseHelper()));
    return dictionaryProvider.getDpdRootFamily(wordId);
  }

  getDpdCompoundFamilies(int wordId) {
    final dictionaryProvider =
        DictionarySerice(DictionaryDatabaseRepository(DatabaseHelper()));
    return dictionaryProvider.getDpdCompoundFamilies(wordId);
  }

  getDpdFreq(int wordId) {
    final dictionaryProvider =
        DictionarySerice(DictionaryDatabaseRepository(DatabaseHelper()));
    return dictionaryProvider.getFrequencyDataForHeadword(wordId);
  }
}
