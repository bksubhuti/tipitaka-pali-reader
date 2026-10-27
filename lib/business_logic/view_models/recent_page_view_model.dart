import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/reading_place.dart';
import '../../services/repositories/recent_repo.dart';
import '../../ui/screens/home/openning_books_provider.dart';
import '../../ui/screens/reader/controller/reader_view_controller.dart';
import '../../ui/screens/reader/mobile_reader_container.dart';
import '../../utils/platform_info.dart';
import '../models/book.dart';
import '../models/recent.dart';

class RecentPageViewModel extends ChangeNotifier {
  final RecentRepository repository;
  RecentPageViewModel(this.repository) {
    recentChanges.addListener(fetchRecents);
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    recentChanges.removeListener(fetchRecents);
    super.dispose();
  }

  //
  List<Recent> _recents = [];
  List<Recent> get recents => _recents;

  Future<void> fetchRecents() async {
    final recents = await repository.getRecents();
    if (_disposed) return;
    _recents = recents;
    notifyListeners();
  }

  /// Goes back to where the reader last was: in its own tab when the book
  /// is open, there at once, else opened at that page.
  void openPlace(ReadingPlace place, BuildContext context) {
    final books = context.read<OpenningBooksProvider>();
    final at = books.books.indexWhere((b) =>
        (b['book'] as Book).id == place.bookId &&
        ReaderViewController.open.containsKey(b['uuid']));
    if (at != -1) {
      final uuid = books.books[at]['uuid'] as String;
      books.updateSelectedBookIndex(at, forceNotify: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ReaderViewController.open[uuid]
            ?.onGoto(pageNumber: place.page, bookUuid: uuid);
      });
    } else {
      books.add(
          book: Book(id: place.bookId, name: place.bookName),
          currentPage: place.page);
    }
    if (Mobile.isPhone(context)) {
      MobileReaderContainer.show(context);
    }
  }

  Future<void> delete(Recent recent) async {
    _recents.remove(recent);
    notifyListeners();
    await repository.delete(recent);
  }

  Future<void> deleteAll() async {
    _recents.clear();
    ReadingPlace.clear();
    notifyListeners();
    await repository.deleteAll();
  }

  void openBook(Recent recent, BuildContext context) async {
    final book = Book(id: recent.bookID, name: recent.bookName!);
    final openningBookProvider = context.read<OpenningBooksProvider>();
    openningBookProvider.add(book: book, currentPage: recent.pageNumber);

    if (Mobile.isPhone(context)) {
      // Navigator.pushNamed(context, readerRoute,
      //     arguments: {'book': bookItem.book});
      MobileReaderContainer.show(context);
    }

    // update recents
    _recents = await repository.getRecents();
    notifyListeners();
  }
}
