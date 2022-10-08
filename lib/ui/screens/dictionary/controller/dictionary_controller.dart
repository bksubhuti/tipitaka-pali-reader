// ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart';

import '../../../../business_logic/models/definition.dart';
import '../../../../services/database/database_helper.dart';
import '../../../../services/database/dictionary_service.dart';
import '../../../../services/repositories/dictionary_repo.dart';
import 'dictionary_state.dart';
import 'package:flutter/services.dart';
import 'package:tipitaka_pali/services/prefs.dart';

// global variable
ValueNotifier<String?> globalLookupWord = ValueNotifier<String?>(null);

enum DictAlgorithm { Auto, TPR, DPR }

extension ParseToString on DictAlgorithm {
  String toStr() {
    return toString().split('.').last;
  }
}

class DictionaryController with ChangeNotifier {
  String? _lookupWord = '';
  String? get lookupWord => _lookupWord;
  BuildContext context;
  List<String> words = [];
  String lastWord = "";
  int wordIndex = 0;

  DictionaryState _dictionaryState = const DictionaryState.initial();
  DictionaryState get dictionaryState => _dictionaryState;

  DictAlgorithm _currentAlgorithmMode = DictAlgorithm.Auto;
  DictAlgorithm get currentAlgorithmMode => _currentAlgorithmMode;

  // TextEditingController textEditingController = TextEditingController();

  DictionaryController({required this.context, String? lookupWord})
      : _lookupWord = lookupWord;

  void onLoad() {
    debugPrint('init dictionary controller');
    globalLookupWord.addListener(_lookupWordListener);

    if (_lookupWord != null) {
      _lookupDefinition();
    }
  }

  @override
  void dispose() {
    debugPrint('dictionary Controller is disposed');
    globalLookupWord.removeListener(_lookupWordListener);
    super.dispose();
  }

  void _lookupWordListener() {
    if (globalLookupWord.value != null) {
      _lookupWord = globalLookupWord.value;
      debugPrint('lookup word: $_lookupWord');
      _lookupDefinition();
    }
  }

  Future<void> _lookupDefinition() async {
    _dictionaryState = const DictionaryState.loading();
    notifyListeners();
    // loading definitions
    final definition = await loadDefinition(_lookupWord!);
    if (definition.isEmpty) {
      _dictionaryState = const DictionaryState.noData();
      notifyListeners();
    } else {
      _dictionaryState = DictionaryState.data(definition);
      notifyListeners();
    }
  }

  Future<String> loadDefinition(String word) async {
    // use only if setting is good in prefs
    if (Prefs.saveClickToClipboard == true) {
      await Clipboard.setData(ClipboardData(text: word));
    }
    switch (_currentAlgorithmMode) {
      case DictAlgorithm.Auto:
        return await searchAuto(word);
      case DictAlgorithm.TPR:
        return searchWithTPR(word);
      case DictAlgorithm.DPR:
        return searchWithDPR(word);
    }
  }

  Future<String> searchAuto(String word) async {
    //
    // Audo mode will use TPR algorithm first
    // if defintion was found, will be display this definition
    // Otherwise will be display result of DPR a

    final before = DateTime.now();

    String definition = await searchWithTPR(word);
    if (definition.isEmpty) definition = await searchWithDPR(word);
    final after = DateTime.now();
    final differnt = after.difference(before);
    debugPrint('compute time: $differnt');

    return definition;
  }

  Future<String> searchWithTPR(String word) async {
    // looking up using estimated stem word
    final dictionaryProvider =
        DictionarySerice(DictionaryDatabaseRepository(DatabaseHelper()));
    final definitions =
        await dictionaryProvider.getDefinition(word, isAlreadyStem: false);
    final String dpdHeadWord = await dictionaryProvider.getDpdHeadwords(word);

    if (dpdHeadWord.isNotEmpty) {
      Definition dpdDefinition =
          await dictionaryProvider.getDpdDefinition(dpdHeadWord);
      definitions.insert(0, dpdDefinition);
      definitions.sort((a, b) => a.userOrder.compareTo(b.userOrder));
    }
    if (definitions.isEmpty) return '';

    return _formatDefinitions(definitions);
  }

  Future<String> searchWithDPR(String word) async {
    // looking up using dpr breakup words
    final dictionaryProvider =
        DictionarySerice(DictionaryDatabaseRepository(DatabaseHelper()));

    // frist dpr_stem will be used for stem
    // stem is single word mostly
    final String dprStem = await dictionaryProvider.getDprStem(word);
    final String dpdHeadWord = await dictionaryProvider.getDpdHeadwords(word);
    if (dprStem.isNotEmpty || dpdHeadWord.isNotEmpty) {
      Definition dpdDefinition =
          await dictionaryProvider.getDpdDefinition(dpdHeadWord);

      List<Definition> definitions =
          await dictionaryProvider.getDefinition(dprStem, isAlreadyStem: true);

      debugPrint(dpdDefinition.definition);

      definitions.insert(0, dpdDefinition);
      definitions.sort((a, b) => a.userOrder.compareTo(b.userOrder));

      if (definitions.isNotEmpty) {
        return _formatDefinitions(definitions);
      }
    }

    // not found in dpr_stem
    // will be lookup in dpr_breakup
    // breakup is multi-words
    final String breakupText = await dictionaryProvider.getDprBreakup(word);
    if (breakupText.isEmpty) return '';

    final List<String> words = getWordsFrom(breakup: breakupText);
    // formating header
    String formatedDefintion = '<b>$word</b> - ';
    String firstPartOfBreakupText =
        breakupText.substring(0, breakupText.indexOf(' '));
    firstPartOfBreakupText = firstPartOfBreakupText.replaceAll("-", " · ");
    // final cssColor = Theme.of(context).primaryColor.toCssString();
    String cssColor =
        "#${Theme.of(context).primaryColor.value.toRadixString(16).substring(2)}";
    String csspreFormat =
        '<p style="color:$cssColor; font-size:90%; font-weight=bold">';
    String lastPartOfBreakupText = words.map((word) => word).join(' + ');
    formatedDefintion +=
        '$csspreFormat $firstPartOfBreakupText [ $lastPartOfBreakupText ] </p>';
    // getting definition per word
    for (var word in words) {
      final definitions =
          await dictionaryProvider.getDefinition(word, isAlreadyStem: true);
      // print(definitions);
      if (definitions.isNotEmpty) {
        formatedDefintion += _formatDefinitions(definitions);
      }
    }
    debugPrint(formatedDefintion);
    return formatedDefintion;
  }

  Future<void> onLookup(String word) async {
    _lookupWord = word;
    _lookupDefinition();
  }

  Future<List<String>> getSuggestions(String word) {
    return DictionarySerice(DictionaryDatabaseRepository(DatabaseHelper()))
        .getSuggestions(word);
  }

  String _formatDefinitions(List<Definition> definitions) {
    String formattedDefinition = '';
    for (Definition definition in definitions) {
      formattedDefinition += _addStyleToBook(definition.bookName);
      formattedDefinition += definition.definition;
    }
    return formattedDefinition;
  }

  String _addStyleToBook(String book) {
    // made variables for easy reading.. otherwise long
    String bkColor =
        Theme.of(context).primaryColor.value.toRadixString(16).substring(2);
    String foreColor =
        Theme.of(context).canvasColor.value.toRadixString(16).substring(2);

    return '<h3 style="background-color: #$bkColor; color: #$foreColor; text-align:center;  padding-bottom:5px; padding-top: 5px;">$book</h3>\n<br>\n';
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
    final indexOfLeftBracket = breakup.indexOf(' (');
    final indexOfRightBracket = breakup.indexOf(')');
    var breakupWords = breakup
        .substring(indexOfLeftBracket + 2, indexOfRightBracket)
        .split(', ');
    // cleans up DPR-specific stuff
    breakupWords =
        breakupWords.map((word) => word.replaceAll('`', '')).toList();
    return breakupWords;
  }

  void onModeChanged(DictAlgorithm? value) {
    if (value != null) {
      _currentAlgorithmMode = value;
      _lookupDefinition();
    }
  }

  void onWordClicked(String word) async {
    word = _romoveNonCharacter(word);

    word = word.toLowerCase();
    _lookupWord = word;
/*
    if (!words.contains(_lookupWord) //&&
        /*globalLookupWord.value != lastWord*/) {
      words.add(_lookupWord!);
      //lastWord = globalLookupWord.value!;
    }
// if not null
*/
    _lookupDefinition();
  }

  String _romoveNonCharacter(String word) {
    word = word.replaceAllMapped(
        RegExp(r'[\[\]\+/\.\)\(\-,:;")\\]'), (match) => ' ');
    List<String> ls = word.split(' ');
    // fix for first character being a non-word-char in above list
    // if so, first split will be empty.
    // if length is >1
    if (ls.length > 1 && ls[0].isEmpty) {
      word = ls[1];
    } else {
      word = ls[0];
    }
    word.trim();
    return word;
  }
}
