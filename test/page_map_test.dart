@TestOn('windows || linux || mac-os')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:tipitaka_pali/services/database/sentence_fts_builder.dart';
import 'package:tipitaka_pali/services/repositories/fts_repo.dart';

/// A page that starts part-way through a paragraph is placed where it starts.
///
/// Placed by paragraph, a paragraph running across several pages was filed
/// under the last of them: a hit near its start, in Paramatthadīpanī's
/// paragraph 1462 on page 434, opened on page 441, and the reader highlighted
/// whatever matched there instead.
void main() {
  late Database db;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await db.execute("ATTACH DATABASE ':memory:' AS epi");
    await db.execute("ATTACH DATABASE ':memory:' AS ext");
    await db.execute('CREATE TABLE epi.sentences (book_id TEXT, '
        'para_id INTEGER, line_id INTEGER, vripara TEXT, pali TEXT)');
    await db.execute('CREATE TABLE ext.page_break (book_id TEXT, '
        'para_id INTEGER, line_id INTEGER, tpr_book TEXT, tpr_page INTEGER, '
        'word_index INTEGER, exact INTEGER)');
  });

  tearDown(() async => db.close());

  Future<void> sentence(int para, int line, String pali) => db.rawInsert(
      'INSERT INTO epi.sentences VALUES (?, ?, ?, ?, ?)',
      ['b', para, line, '$para', pali]);

  Future<void> pageStart(int para, int line, int word, int page) =>
      db.rawInsert('INSERT INTO ext.page_break VALUES (?,?,?,?,?,?,?)',
          ['b', para, line, 'tb', page, word, 1]);

  /// The page a hit [wordOffset] words into the unit holding [para] opens.
  Future<int> pageOf(int para, int wordOffset) async {
    final rows = await db.rawQuery(
        'SELECT page, page_map FROM search_unit '
        'WHERE start_para <= ? AND end_para >= ? ORDER BY id LIMIT 1',
        [para, para]);
    final row = rows.single;
    return FtsDatabaseRepository.pageForMatch(
        row['page_map'] as String?, row['page'] as int, wordOffset);
  }

  test('a paragraph across three pages opens each hit on its own page',
      () async {
    // One paragraph of four lines, four words each: page 10 from its start,
    // 11 from line 3, and 12 from the third word of line 4.
    await sentence(1, 1, 'aaa bbb ccc ddd');
    await sentence(1, 2, 'eee fff ggg hhh');
    await sentence(1, 3, 'iii jjj kkk lll');
    await sentence(1, 4, 'mmm nnn ooo ppp');
    await pageStart(1, 1, 0, 10);
    await pageStart(1, 3, 0, 11);
    await pageStart(1, 4, 2, 12);

    await SentenceFtsBuilder.build(db);

    final unit = (await db.rawQuery('SELECT page, page_map FROM search_unit'))
        .single;
    expect(unit['page'], 10, reason: 'the unit starts on the first page');
    expect(unit['page_map'], '0:10,8:11,14:12');

    expect(await pageOf(1, 0), 10); // aaa
    expect(await pageOf(1, 7), 10); // hhh, last word before line 3
    expect(await pageOf(1, 8), 11); // iii
    expect(await pageOf(1, 13), 11); // nnn
    expect(await pageOf(1, 14), 12); // ooo
  });

  test('a page starting on an empty line starts at the next line with text',
      () async {
    await sentence(1, 1, 'aaa bbb');
    await sentence(1, 2, '');
    await sentence(1, 3, 'ccc ddd');
    await pageStart(1, 1, 0, 5);
    await pageStart(1, 2, 0, 6);

    await SentenceFtsBuilder.build(db);

    final map = (await db.rawQuery('SELECT page_map FROM search_unit'))
        .single['page_map'];
    expect(map, '0:5,2:6');
  });

  test('pages that start on paragraphs still map as before', () async {
    await sentence(1, 1, 'aaa bbb ccc');
    await sentence(2, 1, 'ddd eee fff');
    await pageStart(1, 1, 0, 1);
    await pageStart(2, 1, 0, 2);

    await SentenceFtsBuilder.build(db);

    final unit = (await db.rawQuery(
            'SELECT page, page_map FROM search_unit ORDER BY id'))
        .first;
    expect(unit['page'], 1);
    expect(unit['page_map'], '0:1,3:2');
  });
}
