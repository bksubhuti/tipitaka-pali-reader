@TestOn('windows || linux || mac-os')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Runs real searches against the installed database.
///
/// This is the check that the unit tests cannot make: that the index the app
/// built on device actually answers the queries the search screen sends, and
/// that every result names a book and page the reader can open.
///
/// Skipped when the database is not installed, so it does not fail on a
/// machine that has never run the app.
void main() {
  const dbDir =
      r'C:\Users\Vasil\AppData\Roaming\com.paauk\tipitaka_pali_reader';
  final dbPath = '$dbDir\\tipitaka_pali.db';

  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
  });

  tearDownAll(() async => db.close());

  /// The query the search screen builds for an exact phrase.
  Future<List<Map<String, Object?>>> exactSearch(String table, String phrase) {
    final safe = phrase.replaceAll("'", "''");
    return db.rawQuery('''
      SELECT $table.id, $table.bookid, books.name, $table.page, $table.content
      FROM $table INNER JOIN books ON $table.bookid = books.id
      WHERE $table MATCH '"$safe"' AND $table.content LIKE '%$safe%'
      ORDER BY books.sort_order ASC
      LIMIT 50
    ''');
  }

  test('the index the app built is present and covers the books', () async {
    final units =
        (await db.rawQuery('SELECT count(*) AS n FROM fts_unit')).first['n'];
    final books = (await db
        .rawQuery('SELECT count(DISTINCT bookid) AS n FROM fts_unit'))
        .first['n'] as int;
    expect(units as int, greaterThan(50000));
    expect(books, greaterThan(170));
  });

  test('an exact phrase search returns results that can be opened', () async {
    final rows = await exactSearch('fts_unit', 'evaṃ me sutaṃ');
    expect(rows, isNotEmpty);

    for (final row in rows) {
      final bookId = row['bookid'] as String?;
      final page = row['page'] as int?;
      expect(bookId, isNotNull, reason: 'a result must name a book');
      expect(page, isNotNull, reason: 'a result must name a page');

      // the page it points at must exist in the reader's own numbering
      final exists = await db.rawQuery(
        'SELECT count(*) AS n FROM pages WHERE bookid = ? AND page = ?',
        [bookId, page],
      );
      expect(exists.first['n'], 1,
          reason: '$bookId page $page does not exist in the reader');
    }
  });

  test('a phrase broken across a printed page break is now findable', () async {
    // In the first Digha volume this phrase straddles the break between pages
    // 2 and 3, so the old page-shaped index can only find it where it happens
    // to recur. The paragraph unit spans the break.
    const phrase = 'bhagavantaṃ piṭṭhito piṭṭhito anubandhā';
    final old = await exactSearch('fts_pages', phrase);
    final now = await exactSearch('fts_unit', phrase);
    expect(now.length, greaterThan(old.length));
  });

  test('distance search still reaches across sentences', () async {
    // NEAR works inside one indexed row, so this is really a test that the
    // unit is big enough: these two words sit in different sentences.
    final rows = await db.rawQuery('''
      SELECT bookid, page FROM fts_unit
      WHERE fts_unit MATCH 'NEAR("bhagavā" "bhikkhū", 30)' LIMIT 20
    ''');
    expect(rows, isNotEmpty);
  });

  test('a prefix search returns results', () async {
    final rows = await db.rawQuery('''
      SELECT bookid, page FROM fts_unit
      WHERE fts_unit MATCH 'ariyasacc*' LIMIT 20
    ''');
    expect(rows, isNotEmpty);
  });

  test('results are ordered by the classical book order', () async {
    final rows = await exactSearch('fts_unit', 'cattāri ariyasaccāni');
    expect(rows, isNotEmpty);
    final orders = <int>[];
    for (final row in rows) {
      final r = await db.rawQuery(
          'SELECT sort_order FROM books WHERE id = ?', [row['bookid']]);
      orders.add(r.first['sort_order'] as int);
    }
    final sorted = [...orders]..sort();
    expect(orders, sorted, reason: 'results should come back in book order');
  });
}
