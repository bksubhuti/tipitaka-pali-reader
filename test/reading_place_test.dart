import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tipitaka_pali/business_logic/models/book.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/reading_place.dart';

/// Recent noted a book at the page it opened on; reading on to the third
/// chapter left it there. The reading place follows every page, and is
/// saved, at most once a second, for Recent to show first.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    Prefs.instance = await SharedPreferences.getInstance();
  });

  test('follows the page at once, and saves it a second later', () {
    fakeAsync((time) {
      final book = Book(id: 'attha_ma_01_01', name: 'mūlapaṇṇāsaaṭṭhakathā');
      for (var page = 10; page <= 30; page++) {
        ReadingPlace.note(book, page);
      }
      expect(ReadingPlace.current.value!.page, 30);
      expect(Prefs.readingPlacePage, isNot(30), reason: 'not written yet');
      time.elapse(const Duration(seconds: 1));
      expect(Prefs.readingPlaceBook, 'attha_ma_01_01');
      expect(Prefs.readingPlacePage, 30);
    });
  });

  test('clearing Recent forgets it', () {
    ReadingPlace.clear();
    expect(ReadingPlace.current.value, isNull);
    expect(Prefs.readingPlaceBook, '');
  });
}
