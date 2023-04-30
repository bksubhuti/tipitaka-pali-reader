import 'dart:math';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../business_logic/models/book.dart';
import '../../../services/prefs.dart';

class OpenningBooksProvider extends ChangeNotifier {
  final List<Map<String, dynamic>> _books = [];
  List<Map<String, dynamic>> get books => _books;

  int _selectedBookIndex = 0;
  int get selectedBookIndex => _selectedBookIndex;

  void add({required Book book, int? currentPage, String? textToHighlight}) {
    var uuid = const Uuid().v4();
    _selectedBookIndex = Prefs.isNewTabAtEnd ? _books.length : 0;
    debugPrint('Adding $_selectedBookIndex');
    _books.insert(_selectedBookIndex, {
      'book': book,
      'uuid': uuid,
      'current_page': currentPage,
      'text_to_highlight': textToHighlight,
    });
    notifyListeners();
  }

  void remove({int? index}) {
    final indexToRemove = index ??= _selectedBookIndex;
    _books.removeAt(indexToRemove);
    if (Prefs.isNewTabAtEnd) {
      // only need to select another tab if the current one is the one removed
      // in that case we select the tab to the right of the removed one (as does
      // the chrome browser)
      if (indexToRemove <= _selectedBookIndex) {
        _selectedBookIndex = min(_books.length - 1, _selectedBookIndex);
      }
    } else {
      _selectedBookIndex = 0;
    }
    notifyListeners();
  }

  void removeAll() {
    books.clear();
    _selectedBookIndex = 0;
    notifyListeners();
  }

  void update({required int newPageNumber}) {
    var current = books[_selectedBookIndex];
    current['current_page'] = newPageNumber;
    books[_selectedBookIndex] = current;
  }

  void updateSelectedBookIndex(int index, {bool forceNotify = false}) {
    _selectedBookIndex = index;
    if (forceNotify) {
      notifyListeners();
    }
  }

  void swap(int source, int target) {
    var tmp = books[source];
    books[source] = books[target];
    books[target] = tmp;
    notifyListeners();
  }
}
