import 'package:flutter/material.dart';
import 'package:tipitaka_pali/business_logic/models/index.dart';
import 'package:tipitaka_pali/business_logic/models/search_result.dart';
import 'package:tipitaka_pali/business_logic/models/search_suggestion.dart';
import 'package:tipitaka_pali/services/search_service.dart';
import 'package:tipitaka_pali/utils/mm_string_normalizer.dart';

import '../../routes.dart';

class SearchViewModel extends ChangeNotifier {
  List<SearchSuggestion> suggestions = [];
  List<Index>? results;
  bool isSearching = false;
  String _searchWord = '';

  String get searchWord => _searchWord;

  Future<void> getSuggestions(String filterWord) async {
    suggestions = await SearchService.getSuggestions(filterWord);
    notifyListeners();
  }

  Future<void> clearSuggestions() async {
    suggestions.clear();
    notifyListeners();
  }

  Future<void> doSearch(String searchWord) async {
    _searchWord = searchWord;
    if (results != null) {
      results?.clear();
    }
    _searchWord = MMStringNormalizer.normalize(_searchWord);
    isSearching = true;
    notifyListeners();
    results = await SearchService.getResults(_searchWord);
    isSearching = false;
    notifyListeners();
  }

  void openSearchResult(BuildContext context, String searchWord) {
    Navigator.pushNamed(context, searchResultRoute, arguments: {
      'searchWord': searchWord,
    });
  }

  void openBook(SearchResult result, BuildContext context) {
    Navigator.pushNamed(context, readerRoute, arguments: {
      'book': result.book,
      'currentPage': result.pageNumber,
      'textToHighlight': _searchWord
    });
  }
}
