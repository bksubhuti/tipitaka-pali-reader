@TestOn('windows || linux || mac-os')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:tipitaka_pali/services/database/legacy_data_retirement.dart';

/// Retirement removes the canon's page text once the sentences can serve it.
///
/// The thing worth guarding is what it does *not* remove. ePitaka carries the
/// canon, not the books a reader imported from HTML or installed from an
/// extension zip. Those live in `pages` and nowhere else, so dropping the
/// table outright would delete them with no way back.
void main() {
  late Database db;

  /// A main database holding two books' pages: one the sentence data covers,
  /// one it does not.
  Future<void> build({required bool coverImported}) async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await db.execute('CREATE TABLE pages (id INTEGER PRIMARY KEY, '
        'bookid TEXT, page INTEGER, content TEXT, paranum TEXT)');
    await db.execute("INSERT INTO pages (bookid, page, content, paranum) "
        "VALUES ('mula_di_01', 1, '<p>canon</p>', '1')");
    await db.execute("INSERT INTO pages (bookid, page, content, paranum) "
        "VALUES ('annya_ebook_01', 1, '<p>imported</p>', '')");

    await db.execute("ATTACH DATABASE ':memory:' AS ext");
    await db.execute('CREATE TABLE ext.page_break (book_id TEXT, '
        'para_id INTEGER, line_id INTEGER, tpr_book TEXT, tpr_page INTEGER, '
        'word_index INTEGER, exact INTEGER)');
    await db.execute("INSERT INTO ext.page_break VALUES "
        "('di01', 1, 1, 'mula_di_01', 1, 0, 1)");
    if (coverImported) {
      await db.execute("INSERT INTO ext.page_break VALUES "
          "('eb01', 1, 1, 'annya_ebook_01', 1, 0, 1)");
    }

    // The word list rebuild reads sentences; give it one so run() completes.
    await db.execute("ATTACH DATABASE ':memory:' AS epi");
    await db.execute('CREATE TABLE epi.sentences (book_id TEXT, '
        'para_id INTEGER, line_id INTEGER, vripara TEXT, pali TEXT)');
    await db.execute("INSERT INTO epi.sentences VALUES "
        "('di01', 1, 1, '1', 'evaṃ me sutaṃ')");
  }

  tearDown(() async => db.close());

  test('a book the sentences do not cover keeps its pages', () async {
    await build(coverImported: false);
    await LegacyDataRetirement.run(db);

    final rows = await db.rawQuery('SELECT bookid FROM pages');
    expect(rows.map((r) => r['bookid']), ['annya_ebook_01'],
        reason: 'the imported book exists nowhere else');
  });

  test('the table is dropped when nothing is left to keep', () async {
    await build(coverImported: true);
    await LegacyDataRetirement.run(db);

    expect(await LegacyDataRetirement.hasLegacyPages(db), isFalse,
        reason: 'keeping an empty table would waste the space retirement '
            'exists to reclaim');
  });

  test('retirement does not ask to run again afterwards', () async {
    // isPending used to mean "does the table exist", which stayed true once a
    // book was kept, so the whole retirement including VACUUM repeated on
    // every start.
    await build(coverImported: false);
    expect(await LegacyDataRetirement.isPending(db), isTrue);

    await LegacyDataRetirement.run(db);
    expect(await LegacyDataRetirement.isPending(db), isFalse);
  });

  test('the word list is rebuilt from the sentences', () async {
    await build(coverImported: true);
    await LegacyDataRetirement.run(db);

    final rows =
        await db.rawQuery("SELECT word FROM words ORDER BY word");
    expect(rows.map((r) => r['word']), ['evaṃ', 'me', 'sutaṃ']);
  });

  setUpAll(sqfliteFfiInit);
}
