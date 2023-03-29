import 'package:flutter/material.dart';
import 'package:tipitaka_pali/app.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/ui/screens/home/search_page/search_page.dart';
import 'package:tipitaka_pali/utils/pali_script.dart';
import 'package:tipitaka_pali/utils/pali_script_converter.dart';
import 'package:tipitaka_pali/utils/script_detector.dart';

import '../../routes.dart';
import '../../services/search_service.dart';
import '../models/search_suggestion.dart';

class SearchPageViewModel extends ChangeNotifier {
  final List<SearchSuggestion> _suggestions = [];
  List<SearchSuggestion> get suggestions => _suggestions;

  late QueryMode _queryMode;
  QueryMode get queryMode => _queryMode;

  late int _wordDistance;
  int get wordDistance => _wordDistance;

  bool isSearching = false;
  bool _isFirstWord = true;
  bool get isFirstWord => _isFirstWord;
  bool _isFuzzy = false;
  set isFuzzy(bool fz) {
    _isFuzzy = fz;
  }

  void init() {
    int index = Prefs.queryModeIndex;
    _queryMode = QueryMode.values[index];
    _wordDistance = Prefs.wordDistance;
    isFuzzy = Prefs.isFuzzy;
  }

  Future<void> onTextChanged(String filterWord) async {
    filterWord = filterWord.trim();
    if (filterWord.isEmpty) {
      suggestions.clear();
      notifyListeners();
      return;
    }
    // loading suggested words
    final inputScriptLanguage = ScriptDetector.getLanguage(filterWord);
    myLogger.i('input language is $inputScriptLanguage');

    myLogger.i('original searchword: $filterWord');
    if (inputScriptLanguage != Script.roman) {
      filterWord = PaliScript.getRomanScriptFrom(
          script: inputScriptLanguage, text: filterWord);
    }
    myLogger.i('searchword in roman: $filterWord');
    final words = filterWord.split(' ');
    if (words.length == 1) {
      _isFirstWord = true;
    } else {
      _isFirstWord = false;
    }
    // print('is first word: $_isFirstWord');
    _suggestions.clear();
    _suggestions
        .addAll(await SearchService.getSuggestions(words.last, _isFuzzy));
    notifyListeners();
  }

  Future<void> clearSuggestions() async {
    suggestions.clear();
    notifyListeners();
  }

  void onSubmmited(BuildContext context, String searchWord, QueryMode queryMode,
      int wordDistance) {
    final inputScriptLanguage = ScriptDetector.getLanguage(searchWord);
    if (inputScriptLanguage != Script.roman) {
      searchWord = PaliScript.getRomanScriptFrom(
          script: inputScriptLanguage, text: searchWord);
    }

    Navigator.pushNamed(context, searchResultRoute, arguments: {
      'searchWord': searchWord,
      'queryMode': queryMode,
      'wordDistance': wordDistance
    });
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
}
