import 'package:tipitaka_pali/business_logic/models/dpd_compound_family.dart';
import 'package:tipitaka_pali/business_logic/models/dpd_inflection.dart';
import 'package:tipitaka_pali/business_logic/models/freq.dart';
import 'package:tipitaka_pali/services/prefs.dart';

import '../../business_logic/models/definition.dart';
import '../../business_logic/models/dpd_root_family.dart';
import '../../utils/pali_stemmer.dart';
import '../repositories/dictionary_repo.dart';

const kdartTheme = 'default_dark_theme';
const kblackTheme = 'black';

class DictionarySerice {
  DictionarySerice(this.dictionaryRepository);
  final DictionaryRepository dictionaryRepository;

  /// One definition per DPD dictionary switched on, in dictionary order.
  Future<List<Definition>> getDpdDefinition(String headword) async {
    final definitions = await dictionaryRepository.getDpdDefinition(headword);
    for (final definition in definitions) {
      if (Prefs.hideIPA) {
        definition.definition = removeIPA(definition.definition);
      }
      if (Prefs.hideSanskrit) {
        definition.definition = removeSanskritItems(definition.definition);
      }
      definition.definition = removeNotes(definition.definition);
    }
    return definitions;
  }

  Future<Definition> getDpdGrammarDefinition(String word) async {
    final definition = await dictionaryRepository.getDpdGrammarDefinition(word);
    return definition;
  }

  Future<List<Definition>> getDefinition(String word,
      {bool isAlreadyStem = false}) async {
    if (!isAlreadyStem) {
      word = PaliStemmer.getStem(word);
    }

    // final DatabaseHelper databaseHelper = DatabaseHelper();
    // final DictionaryRepository dictRepository =
    //     DictionaryDatabaseRepository(databaseHelper);

    // lookup using estimated stem word
    // print('dict word: $stemWord');
    final definitions = await dictionaryRepository.getDefinition(word);
    return definitions;

    // return _formatDefinitions(definitions);
  }

  Future<List<String>> getSuggestions(String word) async {
    return dictionaryRepository.getSuggestions(word);
  }

  Future<String> getDpdWordSplit(String word) async {
    return dictionaryRepository.getDpdWordSplit(word);
  }

  Future<String> getDprStem(String word) async {
    return dictionaryRepository.getDprStem(word);
  }

  Future<DpdInflection?> getDpdInflection(int wordId) async {
    return dictionaryRepository.getDpdInflection(wordId);
  }

  Future<List<DpdCompoundFamily>?> getDpdCompoundFamilies(int wordId,
      {String lang = ''}) async {
    return dictionaryRepository.getDpdCompoundFamilies(wordId, lang: lang);
  }

  Future<DpdRootFamily?> getDpdRootFamily(int wordId,
      {String lang = ''}) async {
    return dictionaryRepository.getDpdRootFamily(wordId, lang: lang);
  }

  Future<Freq?> getFrequencyDataForHeadword(int wordId) async {
    return dictionaryRepository.getFrequencyDataForHeadword(wordId);
  }

  Future<String> getDpdHeadwords(String word) async {
    return dictionaryRepository.getDpdHeadwords(word);
  }

  Future<String> getDpdLikeHeadwords(String word) async {
    return dictionaryRepository.getDpdLikeHeadwords(word);
  }

  String removeIPA(String content) {
    final regexPattern = RegExp(
        r'<tr>\s*<th[^>]*>\s*IPA\s*</th>\s*<td[^>]*>.*?</td>\s*</tr>',
        caseSensitive: false,
        multiLine: true,
        dotAll: true // Allows '.' to match newline characters as well
        );

    return content.replaceAll(regexPattern, ''); // Replace with empty string
  }

  String removeSanskritItems(String content) {
    final regexPattern = RegExp(
        r'<tr>\s*<th[^>]*>\s*(Sanskrit|Sanskrit Root)\s*</th>\s*<td[^>]*>.*?</td>\s*</tr>',
        caseSensitive: false,
        multiLine: true,
        dotAll: true);

    return content.replaceAll(regexPattern, '');
  }

  String removeNotes(String content) {
    // This regex looks for a table row where the header is exactly "Notes"
    final regexPattern = RegExp(
        r'<tr>\s*<th[^>]*>\s*Notes\s*</th>\s*<td[^>]*>.*?</td>\s*</tr>',
        caseSensitive: false,
        multiLine: true,
        dotAll: true);

    return content.replaceAll(regexPattern, '');
  }
}
