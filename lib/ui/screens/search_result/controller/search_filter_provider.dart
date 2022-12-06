import 'package:flutter/material.dart';

import '../../../../services/prefs.dart';

class SearchFilterController extends ChangeNotifier {
  final Map<String, String> _mainCategoryFilters = const {
    'mula': 'Mūla',
    'attha': 'Aṭṭhakathā',
    'tika': 'Ṭīka',
    'annya': 'Annya'
  };
  final Map<String, String> _subCategoryFilters = const {
    '_vi': 'Vinaya',
    '_di': 'Dīgha',
    '_ma': 'Majjhima',
    '_sa': 'Saṃyutta',
    '_an': 'Aṅguttara',
    '_ku': 'Khuddaka',
    '_bi': 'Abhidhamma',
    '_pe': 'English'
  };
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
}
