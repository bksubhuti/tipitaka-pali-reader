import 'package:flutter/material.dart';
import 'dart:convert';

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
    '_bi': 'Abhidhamma'
  };
  Map<String, String> get mainCategoryFilters => _mainCategoryFilters;

  Map<String, String> get subCategoryFilters => _subCategoryFilters;

  //late List<String> _selectedMainCategoryFilters;
  late final List<String> _selectedSubCategoryFilters;

  List<String> get selectedMainCategoryFilters =>
      json.decode(Prefs.selectedMainCategoryFilters).cast<String>();

  List<String> get selectedSubCategoryFilters =>
      json.decode(Prefs.selectedSubCategoryFilters).cast<String>();

  void onMainFilterChange(String filterID, bool isSelected) {
    List<String> list =
        json.decode(Prefs.selectedMainCategoryFilters).cast<String>();
    if (isSelected) {
      //_selectedMainCategoryFilters.add(filterID);
      list.add(filterID);
    } else {
      list.remove(filterID);
    }
    Prefs.selectedMainCategoryFilters = json.encode(list);
    notifyListeners();
  }

  void onSubFilterChange(String filterID, bool isSelected) {
    List<String> list =
        json.decode(Prefs.selectedSubCategoryFilters).cast<String>();
    if (isSelected) {
      list.add(filterID);
    } else {
      list.remove(filterID);
    }
    Prefs.selectedSubCategoryFilters = json.encode(list);
    notifyListeners();
  }
}
