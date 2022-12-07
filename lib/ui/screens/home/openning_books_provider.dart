import 'package:flutter/material.dart';

import '../../../business_logic/models/book.dart';

class OpenningBooksProvider extends ChangeNotifier {
  final List<Map<String, dynamic>> _books = [];
  List<Map<String, dynamic>> get books => _books;

  int _selectedBookIndex = 0;
  int get selectedBookIndex => _selectedBookIndex;

  void add({required Book book, int? currentPage, String? textToHighlight}) {
    _books.insert(0, {
      'book': book,
      'current_page': currentPage,
      'text_to_highlight': textToHighlight,
    });
    notifyListeners();
  }

  void remove({int? index}) {
    index ??= selectedBookIndex;
    books.removeAt(index);
      _selectedBookIndex = 0;
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

  void updateSelectedBookIndex(int index,{bool forceNotify =false}) {
    _selectedBookIndex = index;
    if(forceNotify){

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
