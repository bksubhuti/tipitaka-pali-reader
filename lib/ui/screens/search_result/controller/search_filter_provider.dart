import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../services/prefs.dart';
import '../../../../services/provider/script_language_provider.dart';
import '../../../../utils/pali_script.dart';
import '../../../../business_logic/models/book.dart';
import '../../../../business_logic/models/search_result.dart';

class SearchFilterController extends ChangeNotifier {
  final BuildContext context;
  final Map<String, String> _mainCategoryFilters = {};
  final Map<String, String> _subCategoryFilters = {};

  List<Book> _postSearchBooks = [];
  Set<String> _selectedPostSearchBookIds = {};

  List<Book> get postSearchBooks => _postSearchBooks;
  Set<String> get selectedPostSearchBookIds => _selectedPostSearchBookIds;

  SearchFilterController({required this.context}) {
    _subCategoryFilters['_vi'] = localScript(context, 'Vinaya');
    _subCategoryFilters['_di'] = localScript(context, 'Dīgha');
    _subCategoryFilters['_ma'] = localScript(context, 'Majjhima');
    _subCategoryFilters['_sa'] = localScript(context, 'Saṃyutta');
    _subCategoryFilters['_an'] = localScript(context, 'Aṅguttara');
    _subCategoryFilters['_ku'] = localScript(context, 'Khuddaka');
    _subCategoryFilters['_bi'] = localScript(context, 'Abhidhamma');
    _subCategoryFilters['_pe'] = localScript(context, 'English');

    _mainCategoryFilters['mula'] = localScript(context, 'Mūla');
    _mainCategoryFilters['attha'] = localScript(context, 'Aṭṭhakathā');
    _mainCategoryFilters['tika'] = localScript(context, 'Ṭīka');
    _mainCategoryFilters['annya'] = localScript(context, 'Annya');
  }

  String localScript(BuildContext context, String s) {
    return PaliScript.getScriptOf(
        script: context.read<ScriptLanguageProvider>().currentScript,
        romanText: s);
  }

  Map<String, String> get mainCategoryFilters => _mainCategoryFilters;

  Map<String, String> get subCategoryFilters => _subCategoryFilters;

  List<String> get selectedMainCategoryFilters =>
      Prefs.selectedMainCategoryFilters;

  List<String> get selectedSubCategoryFilters =>
      Prefs.selectedSubCategoryFilters;

  void onMainFilterChange(String filterID, bool isSelected) {
    List<String> list = Prefs.selectedMainCategoryFilters;
    if (isSelected) {
      list.add(filterID);
    } else {
      list.remove(filterID);
    }
    Prefs.selectedMainCategoryFilters = list;
    notifyListeners();
  }

  void onSubFilterChange(String filterID, bool isSelected) {
    List<String> list = Prefs.selectedSubCategoryFilters;
    if (isSelected) {
      list.add(filterID);
    } else {
      list.remove(filterID);
    }
    Prefs.selectedSubCategoryFilters = list;
    notifyListeners();
  }

  void onSelectAll() {
    Prefs.selectedMainCategoryFilters = List.from(_mainCategoryFilters.keys);
    Prefs.selectedSubCategoryFilters = List.from(_subCategoryFilters.keys);
    notifyListeners();
  }

  void onSelectNone() {
    // In mula, we want to search most of the time,
    Prefs.selectedMainCategoryFilters = ['mula'];
    // Prefs.selectedMainCategoryFilters.add('mula');
    Prefs.selectedSubCategoryFilters = [];
    notifyListeners();
  }

  void updatePostSearchBooks(List<SearchResult> results) {
    _postSearchBooks.clear();
    _selectedPostSearchBookIds.clear();
    final uniqueBooks = <String, Book>{};
    for (var result in results) {
      if (!uniqueBooks.containsKey(result.book.id)) {
        uniqueBooks[result.book.id] = result.book;
        _selectedPostSearchBookIds.add(result.book.id);
      }
    }
    _postSearchBooks = uniqueBooks.values.toList();
    // Do not notifyListeners() here, as this is called during initialization
  }

  void onPostSearchBookChange(String bookId, bool isSelected) {
    if (isSelected) {
      _selectedPostSearchBookIds.add(bookId);
    } else {
      _selectedPostSearchBookIds.remove(bookId);
    }
    notifyListeners();
  }

  void onSelectAllPostSearchBooks() {
    _selectedPostSearchBookIds = _postSearchBooks.map((b) => b.id).toSet();
    notifyListeners();
  }

  void onSelectNonePostSearchBooks() {
    _selectedPostSearchBookIds.clear();
    notifyListeners();
  }
}
