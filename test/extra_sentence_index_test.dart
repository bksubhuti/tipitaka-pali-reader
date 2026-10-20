@TestOn('windows || linux || mac-os')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:tipitaka_pali/services/database/sentence_fts_builder.dart';
import 'package:tipitaka_pali/services/database/unit_text.dart';

/// Three books are not in ePitaka and were converted from TPR's own text into
/// `ext.extra_sentence`. The reader showed them, but the index read only
/// `epi.sentences`, so no search could find them, and nothing said so.
void main() {
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await db.execute("ATTACH DATABASE ':memory:' AS epi");
    await db.execute("ATTACH DATABASE ':memory:' AS ext");
    await db.execute('CREATE TABLE books (id TEXT PRIMARY KEY, name TEXT)');
    await db.execute('CREATE TABLE epi.sentences (book_id TEXT, '
        'para_id INTEGER, line_id INTEGER, vripara TEXT, pali TEXT)');
    await db.execute('CREATE TABLE ext.extra_sentence (book_id TEXT, '
        'para_id INTEGER, line_id INTEGER, pali TEXT)');
    await db.execute('CREATE TABLE ext.page_break (book_id TEXT, '
        'para_id INTEGER, line_id INTEGER, word_index INTEGER, '
        'tpr_book TEXT, tpr_page INTEGER)');

    await db.execute(
        "INSERT INTO epi.sentences VALUES ('Moh', 1, 1, '1', 'kiñcāpi khīṇāsavānaṃ')");
    await db.execute("INSERT INTO ext.extra_sentence VALUES "
        "('annya_sadda_16', 1, 1, 'Sa vutto tattha paṭhamā, "
        "atthamattavivacchayā.')");
    await db.execute("INSERT INTO ext.page_break VALUES "
        "('Moh', 1, 1, 0, 'tika_bi_13', 1), "
        "('annya_sadda_16', 1, 1, 0, 'annya_sadda_16', 1)");
  });

  tearDown(() => db.close());

  test('a book held only in the extension is indexed', () async {
    await SentenceFtsBuilder.build(db);
    final hit = await db.rawQuery(
        "SELECT u.bookid FROM fts_unit f JOIN search_unit u ON u.id = f.rowid "
        "WHERE fts_unit MATCH '\"atthamattavivacchayā\"'");
    expect(hit.map((r) => r['bookid']), ['annya_sadda_16']);

    final epitaka = await db.rawQuery(
        "SELECT u.bookid FROM fts_unit f JOIN search_unit u ON u.id = f.rowid "
        "WHERE fts_unit MATCH '\"khīṇāsavānaṃ\"'");
    expect(epitaka.map((r) => r['bookid']), ['tika_bi_13']);
  });

  test('its text is rebuilt from the extension for the result', () async {
    final unit = await UnitText.paliWithParagraphs(db,
        epiBook: 'annya_sadda_16', startPara: 1, endPara: 1);
    expect(unit.text, 'Sa vutto tattha paṭhamā, atthamattavivacchayā.');
  });
}
