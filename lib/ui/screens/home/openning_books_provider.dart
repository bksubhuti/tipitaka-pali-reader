import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:tipitaka_pali/ui/screens/home/search_page/search_page.dart';
import 'package:uuid/uuid.dart';

import '../../../business_logic/models/book.dart';
import '../../../services/prefs.dart';

class OpenningBooksProvider extends ChangeNotifier {
  final List<Map<String, dynamic>> _books = [];
  List<Map<String, dynamic>> get books => _books;

  int _selectedBookIndex = 0;
  int get selectedBookIndex => _selectedBookIndex;

  /// Counts every change of the selected book. The tab bar selects quietly,
  /// so that a click does not redraw every reader; this tells only those
  /// who follow the selection, such as the library's tree.
  final ValueNotifier<int> selectionChanges = ValueNotifier(0);

  void add(
      {required Book book,
      int? currentPage,
      String? textToHighlight,
      QueryMode? queryMode}) {
    Prefs.numberBooksOpened++;
    var uuid = const Uuid().v4();
    _selectedBookIndex = Prefs.isNewTabAtEnd ? _books.length : 0;
    _books.insert(_selectedBookIndex, {
      'book': book,
      'uuid': uuid,
      'current_page': currentPage,
      'text_to_highlight': textToHighlight,
      'query_mode': queryMode,
    });
    saveTabs();
    notifyListeners();
  }

  void remove({int? index}) {
    if (_books.isEmpty) return;
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
    saveTabs();
    notifyListeners();
  }

  void removeAll() {
    books.clear();
    _selectedBookIndex = 0;
    saveTabs();
    notifyListeners();
  }

  void update({required int newPageNumber, String? bookUuid}) {
    var current = books[_selectedBookIndex];
    int targetIndex = _selectedBookIndex;

    if (bookUuid != null) {
      final foundIndex =
          books.indexWhere((element) => element['uuid'] == bookUuid);
      if (foundIndex != -1) {
        current = books[foundIndex];
        targetIndex = foundIndex;
      }
    }

    current['current_page'] = newPageNumber;
    // Always save the updated current back to the list at the correct index
    books[targetIndex] = current;
    saveTabs();
  }

  void updateSelectedBookIndex(int index, {bool forceNotify = false}) {
    _selectedBookIndex = index;
    selectionChanges.value++;
    saveTabs();
    if (forceNotify) {
      notifyListeners();
    }
  }

  /// Redraws the open books after a change to how they are laid out, such
  /// as multi-view being turned on, which the reader reads as it draws.
  void layoutChanged() => notifyListeners();

  void swap(int source, int target, {int? selected}) {
    var tmp = books[source];
    books[source] = books[target];
    books[target] = tmp;

    if (selected != null) {
      _selectedBookIndex = selected;
    }

    saveTabs();
    notifyListeners();
  }

  /// Keeps the open books, each with the page at the top of its view, for
  /// reopening at the next start. Only when the reader has turned on
  /// restoring them in Settings › General.
  void saveTabs() {
    if (!Prefs.restoreTabs) return;
    Prefs.savedTabs = jsonEncode({
      'selected': _selectedBookIndex,
      'books': [
        for (final b in _books)
          {
            'id': (b['book'] as Book).id,
            'name': (b['book'] as Book).name,
            'page': b['current_page'],
          }
      ],
    });
  }

  /// The books saved at the end of the last session, as (book, page), and
  /// which of them was selected; empty when there are none.
  static ({List<(Book, int?)> books, int selected}) savedTabs() {
    try {
      final saved = Prefs.savedTabs;
      if (saved == null) return (books: const [], selected: 0);
      final json = jsonDecode(saved) as Map<String, dynamic>;
      return (
        books: [
          for (final b in json['books'] as List)
            (
              Book(id: b['id'] as String, name: b['name'] as String),
              b['page'] as int?
            )
        ],
        selected: json['selected'] as int? ?? 0,
      );
    } catch (_) {
      return (books: const [], selected: 0);
    }
  }

  /// Opens the saved books again, in their order, each on its page.
  void restore(List<(Book, int?)> saved, int selected) {
    for (final (book, page) in saved) {
      _books.add({
        'book': book,
        'uuid': const Uuid().v4(),
        'current_page': page,
        'text_to_highlight': null,
        'query_mode': null,
      });
    }
    _selectedBookIndex = selected.clamp(0, _books.length - 1);
    selectionChanges.value++;
    saveTabs();
    notifyListeners();
  }
}
