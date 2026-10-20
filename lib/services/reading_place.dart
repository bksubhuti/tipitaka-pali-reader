import 'dart:async';

import 'package:flutter/foundation.dart';

import '../business_logic/models/book.dart';
import 'prefs.dart';

/// Where the reader last was: a book and page, kept as the reading moves.
///
/// The Recent list notes a book when it is opened, from the library, a
/// search result or a bookmark, at the page it opened on. Reading on to the
/// third chapter left it there. This is the place itself, updated with every
/// page the reader comes to, so Recent can show it first and go back to it.
///
/// Kept in the preferences, not the database: it changes all the time while
/// reading, and is written at most once a second.
class ReadingPlace {
  const ReadingPlace(this.bookId, this.bookName, this.page);

  final String bookId;
  final String bookName;
  final int page;

  /// The place, as it changes.
  static final ValueNotifier<ReadingPlace?> current = ValueNotifier(_stored());

  static Timer? _save;

  static ReadingPlace? _stored() {
    try {
      final id = Prefs.readingPlaceBook;
      if (id.isEmpty) return null;
      return ReadingPlace(
          id, Prefs.readingPlaceBookName, Prefs.readingPlacePage);
    } catch (_) {
      return null; // preferences not ready, as in a test
    }
  }

  /// The reader is at [page] of [book].
  static void note(Book book, int page) {
    final now = current.value;
    if (now != null && now.bookId == book.id && now.page == page) return;
    current.value = ReadingPlace(book.id, book.name, page);
    _save?.cancel();
    _save = Timer(const Duration(seconds: 1), () {
      Prefs.readingPlaceBook = book.id;
      Prefs.readingPlaceBookName = book.name;
      Prefs.readingPlacePage = page;
    });
  }

  /// Forgets it, with the rest of Recent.
  static void clear() {
    _save?.cancel();
    current.value = null;
    Prefs.readingPlaceBook = '';
  }
}
