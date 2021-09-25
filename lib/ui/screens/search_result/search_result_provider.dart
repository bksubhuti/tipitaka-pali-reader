import 'package:flutter/material.dart';
import 'package:tipitaka_pali/business_logic/models/index.dart';
import 'package:tipitaka_pali/business_logic/models/search_result.dart';
import 'package:tipitaka_pali/services/search_service.dart';
import 'package:tipitaka_pali/ui/screens/search_result/search_filter_provider.dart';
import 'package:tipitaka_pali/ui/screens/search_result/search_result_state.dart';

import '../../../routes.dart';

class SearchResultController extends ChangeNotifier {
  SearchResultController(
      {required this.searchWord, required this.filterController}) {
    _init();
  }
  final String searchWord;
  final SearchFilterController filterController;
  // final SearchFilterNotifier searchFilterNotifier;
  List<Index> _allResults = [];
  List<Index> _filterdResults = [];
  SearchResultState _state = SearchResultState.loading();
  SearchResultState get state => _state;

  void _init() async {
    _allResults = await SearchService.getResults(searchWord);
    if (_allResults.isEmpty) {
      _state = SearchResultState.noData();
      notifyListeners();
      return;
    }
    _filterdResults = _doFilter(filterController);
    _state = SearchResultState.loaded(_filterdResults, getBookCount());
    notifyListeners();
  }

  void onChangeFilter(SearchFilterController filterController) {
    _state = SearchResultState.loading();
    print('calling on filter change');
    _filterdResults = _doFilter(filterController);
   
     _state = SearchResultState.loaded(_filterdResults, getBookCount());
    
    notifyListeners();
  }

  List<Index> _doFilter(SearchFilterController filterController) {
    final selectedMainCategoryFilters =
        filterController.selectedMainCategoryFilters;
    final selectedSubCategoryFilters =
        filterController.selectedSubCategoryFilters;

    final List<Index> firstFilterdList = [];
    final List<Index> secondFilterdList = [];

    // do filter with main category
    selectedMainCategoryFilters.forEach((element) {
      firstFilterdList.addAll(_allResults
          .where((index) => index.bookID!.contains(element))
          .toList());
    });

    // do filter with sub scategory
    selectedSubCategoryFilters.forEach((element) {
      secondFilterdList.addAll(firstFilterdList
          .where((index) => index.bookID!.contains(element))
          .toList());
    });
    // book order was changed while filtering
    // so need to reorder
    secondFilterdList.sort((a, b) => a.pageID.compareTo(b.pageID));
    return secondFilterdList;
  }

  int getBookCount() {
    final books = <String>{};
    _filterdResults.forEach((element) {
      books.add(element.bookID!);
    });
    return books.length;
  }

  Future<SearchResult> getDetailResult(Index index) async {
    return await SearchService.getDetail(searchWord, index);
  }

  void openBook(SearchResult result, BuildContext context) {
    Navigator.pushNamed(context, ReaderRoute, arguments: {
      'book': result.book,
      'currentPage': result.pageNumber,
      'textToHighlight': searchWord
    });
  }
}