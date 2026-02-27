import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../business_logic/models/search_result.dart';
import '../../../../services/search_service.dart';
import '../../../../utils/platform_info.dart';
import '../../home/openning_books_provider.dart';
import '../../home/search_page/search_page.dart';
import '../../reader/mobile_reader_container.dart';
import 'search_filter_provider.dart';
import 'search_result_state.dart';

class SearchResultController extends ChangeNotifier {
  SearchResultController(
      {required this.searchWord,
      required this.queryMode,
      required this.wordDistance,
      required this.filterController});
  final String searchWord;
  final QueryMode queryMode;
  final int wordDistance;
  final SearchFilterController filterController;
  // final SearchFilterNotifier searchFilterNotifier;
  List<SearchResult> _allResults = [];
  List<SearchResult> _filterdResults = [];
  SearchResultState _state = const SearchResultState.loading();
  SearchResultState get state => _state;
  bool _isInitialized = false;

  // String get readerRoute => null;

  void init() async {
    var startTime = DateTime.now();
    _allResults = await SearchService.getResultsByFTS(
        searchWord.toLowerCase(), queryMode, wordDistance);
    _isInitialized = true;
    debugPrint('total load time: ${DateTime.now().difference(startTime)}');
    if (_allResults.isEmpty) {
      _state = const SearchResultState.noData();
      notifyListeners();
      return;
    }
    // filtering results
    _filterdResults = _doFilter(filterController);
    // updating state
    _state = SearchResultState.loaded(_filterdResults, getBookCount());
    notifyListeners();
  }

  void onChangeFilter(SearchFilterController filterController) {
    if (_isInitialized) {
      // change state to loading while filtering
      _state = const SearchResultState.loading();
      notifyListeners();
      // filtering
      _filterdResults = _doFilter(filterController);
      // update state
      _state = SearchResultState.loaded(_filterdResults, getBookCount());
      notifyListeners();
    }
  }

  List<SearchResult> _doFilter(SearchFilterController filterController) {
    final selectedMainCategoryFilters =
        filterController.selectedMainCategoryFilters;
    final selectedSubCategoryFilters =
        filterController.selectedSubCategoryFilters;

    final List<SearchResult> firstFilterdList = [];
    final List<SearchResult> secondFilterdList = [];

    // Filter main category: We use .any() to check the filters
    // while walking through _allResults in its perfect original order.
    if (selectedMainCategoryFilters.isNotEmpty) {
      firstFilterdList.addAll(_allResults.where((searchResult) {
        return selectedMainCategoryFilters
            .any((element) => searchResult.book.id.contains(element));
      }));
    } else {
      firstFilterdList.addAll(_allResults);
    }

    // Filter sub category: We do the same here, maintaining the
    // sequence we just built in firstFilterdList.
    if (selectedSubCategoryFilters.isNotEmpty) {
      secondFilterdList.addAll(firstFilterdList.where((searchResult) {
        return selectedSubCategoryFilters
            .any((element) => searchResult.book.id.contains(element));
      }));
    } else {
      secondFilterdList.addAll(firstFilterdList);
    }

    // Return the list exactly as-is. No .sort() needed!
    return secondFilterdList;
  }

  int getBookCount() {
    final books = <String>{};
    for (var element in _filterdResults) {
      books.add(element.book.id);
    }
    return books.length;
  }

  void openBook(SearchResult result, BuildContext context) {
    final openningBookProvider = context.read<OpenningBooksProvider>();
    openningBookProvider.add(
      book: result.book,
      currentPage: result.pageNumber,
      textToHighlight: searchWord,
    );

    if (Mobile.isPhone(context)) {
      // Navigator.pushNamed(context, readerRoute,
      //     arguments: {'book': bookItem.book});
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const MobileReaderContainer()));
    }
  }
}
