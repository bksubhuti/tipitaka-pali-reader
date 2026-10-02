import 'package:flutter/foundation.dart';
import 'package:tipitaka_pali/business_logic/models/search_history.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/repositories/search_history_repo.dart';
import 'package:tipitaka_pali/ui/screens/home/search_page/search_page.dart';

import '../../services/search_service.dart';
import '../models/search_suggestion.dart';
import 'package:tipitaka_pali/utils/search_input.dart';

// global variable
final ValueNotifier<String?> globalSearchWord = ValueNotifier<String?>(null);

class SearchPageViewModel extends ChangeNotifier {
  final SearchHistoryRepository searchHistoryRepository;
  SearchPageViewModel({
    required this.searchHistoryRepository,
  });

  final ValueNotifier<bool> _isSearching = ValueNotifier<bool>(false);
  ValueNotifier<bool> get isSearching => _isSearching;

  final _suggestions = ValueNotifier<List<SearchSuggestion>>([]);
  ValueListenable<List<SearchSuggestion>> get suggestions => _suggestions;

  final _histories = ValueNotifier<List<SearchHistory>>([]);
  ValueListenable<List<SearchHistory>> get histories => _histories;

//  ValueNotifier<int> _count = ValueNotifier<int>(33);
//  ValueListenable<int> get count => _count;

  int count = 33000000;
  late QueryMode _queryMode;
  QueryMode get queryMode => _queryMode;

  late int _wordDistance;
  int get wordDistance => _wordDistance;

  String _userInput = '';
  bool get isFirstWord => _userInput.split(' ').length == 1;
  bool _isFuzzy = false;
  set isFuzzy(bool fz) {
    _isFuzzy = fz;
  }

  void init() {
    int index = Prefs.queryModeIndex;
    _queryMode = QueryMode.values[index];
    _wordDistance = Prefs.wordDistance;
    isFuzzy = Prefs.isFuzzy;
    // load histories
    searchHistoryRepository.getAll().then((value) {
      value.sort((a, b) => b.dateTime.compareTo(a.dateTime));
      _histories.value = [...value];
    });

    // search
    if (globalSearchWord.value != null) {
      Future.delayed(const Duration(milliseconds: 50), () {
        print('search word: ${globalSearchWord.value}');
        onSubmmited(globalSearchWord.value!);
      });
    }

    // do a check to see if the wordlist was somehow not complete.
    searchHistoryRepository.getWordCount().then((value) {
      count = value;
      notifyListeners();
    });
  }

  Future<void> onTextChanged(String filterWord) async {
    filterWord = filterWord.trim();
    if (filterWord.isEmpty) {
      isSearching.value = false;
      _suggestions.value = [];
      // notifyListeners();
      return;
    }
    // loading suggested words
    isSearching.value = true;
    // Pali in the reader's script, or a translation's words in another:
    // see SearchInput. A translation's words are suggested from the words
    // its index holds, since the word list keeps only Pali and Roman ones.
    final input = SearchInput.of(filterWord);
    if (input.isTranslationOnly) {
      _userInput = input.asTyped;
      _suggestions.value = [
        ...await SearchService.getTranslationSuggestions(
            input.asTyped.split(' ').last)
      ];
      return;
    }
    filterWord = input.pali;
    _userInput = filterWord; // cache the user input
    final words = filterWord.split(' ');
    _suggestions.value = [
      ...await SearchService.getSuggestions(words.last, _isFuzzy)
    ];
    // notifyListeners();
  }

  void onSubmmited(String searchWord) async {
    _userInput = searchWord;
    // save search
    if (!isContainInHistories(_histories.value, searchWord)) {
      await searchHistoryRepository.insert(searchWord);
      final histories = await searchHistoryRepository.getAll();
      histories.sort((a, b) => b.dateTime.compareTo(a.dateTime));
      _histories.value = [...histories];
    }
  }

  void onQueryModeChanged(QueryMode queryMode) {
    _queryMode = queryMode;
    // saving to shared preference
    // int index = _getQueryModeIndex(queryMode);
    Prefs.queryModeIndex = _queryMode.index;
    notifyListeners();
  }

/*
  int _getQueryModeIndex(QueryMode queryMode) {
    switch (queryMode) {
      case QueryMode.exact:
        return 0;
      case QueryMode.prefix:
        return 1;
      case QueryMode.distance:
        return 2;
      case QueryMode.anywhere:
        return 3;
      default:
        return 0;
    }
  }
*/
  void onWordDistanceChanged(int wordDistance) {
    _wordDistance = wordDistance;
    Prefs.wordDistance = wordDistance;
    notifyListeners();
  }

  void onDeleteButtonClicked(String word) async {
    await searchHistoryRepository.delete(word);
    final histories = _histories.value;
    histories.removeWhere((element) => element.word == word);
    _histories.value = [...histories];
  }

  bool isContainInHistories(List<SearchHistory> histories, String word) {
    if (histories.isEmpty) return false;
    histories.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    for (int i = 0; i < histories.length; i++) {
      if (histories[i].word == word) {
        return true;
      }
    }
    // not found
    return false;
  }
}
