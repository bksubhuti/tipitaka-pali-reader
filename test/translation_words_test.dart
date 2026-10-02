@TestOn('windows || linux || mac-os')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:tipitaka_pali/services/database/sentence_fts_builder.dart';

/// Translations in Myanmar, Thai and other scripts with vowel signs must be
/// indexed as whole words. The default tokenizer split them at every sign,
/// so nothing could be suggested and a search matched consonants alone.
void main() {
  late Database db;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await db.execute("ATTACH DATABASE ':memory:' AS epi");
    await db.execute("ATTACH DATABASE ':memory:' AS ext");
    await db.execute("ATTACH DATABASE ':memory:' AS lang_my");
    await db.execute("ATTACH DATABASE ':memory:' AS lang_en");
    await db.execute('CREATE TABLE epi.sentences (book_id TEXT, '
        'para_id INTEGER, line_id INTEGER, vripara TEXT, pali TEXT)');
    await db.execute('CREATE TABLE ext.page_break (book_id TEXT, '
        'para_id INTEGER, line_id INTEGER, tpr_book TEXT, tpr_page INTEGER, '
        'word_index INTEGER, exact INTEGER)');
    for (final code in ['my', 'en']) {
      await db.execute('CREATE TABLE lang_$code.sentences (book_id TEXT, '
          'para_id INTEGER, line_id INTEGER, translation TEXT)');
    }
    await db.execute('CREATE TABLE books (id TEXT, name TEXT)');
    final rows = [
      ['မြတ်စွာဘုရားသည် ထိုရဟန်းတို့၏ စကားစမြည် ပြောဆိုမှုကို', 'They were running'],
      ['စကားလုံးသည် ရှင်းသည်', 'The Blessed One'],
    ];
    for (var para = 1; para <= rows.length; para++) {
      await db.rawInsert('INSERT INTO epi.sentences VALUES (?, ?, ?, ?, ?)',
          ['b', para, 1, '$para', 'evaṃ me sutaṃ $para']);
      await db.rawInsert('INSERT INTO lang_my.sentences VALUES (?, ?, ?, ?)',
          ['b', para, 1, rows[para - 1][0]]);
      await db.rawInsert('INSERT INTO lang_en.sentences VALUES (?, ?, ?, ?)',
          ['b', para, 1, rows[para - 1][1]]);
      await db.rawInsert('INSERT INTO ext.page_break VALUES (?,?,?,?,?,?,?)',
          ['b', para, 1, 'mula_b', para, 0, 1]);
    }
    await SentenceFtsBuilder.build(db, languages: ['en', 'my']);
  });

  tearDown(() => db.close());

  Future<List<String>> words(String prefix) async {
    await db.execute('CREATE VIRTUAL TABLE IF NOT EXISTS temp.v USING '
        "fts5vocab(main, 'fts_translation_unit', 'row')");
    return (await db.rawQuery(
            'SELECT term FROM temp.v WHERE term >= ? AND term < ? '
            'ORDER BY term',
            [prefix, '$prefix\u{10FFFF}']))
        .map((r) => r['term'] as String)
        .toList();
  }

  Future<int> hits(String match) async => (await db.rawQuery(
          'SELECT count(*) AS n FROM fts_translation_unit '
          'WHERE fts_translation_unit MATCH ?',
          [match]))
      .first['n'] as int;

  test('Myanmar words are kept whole, with their vowel signs', () async {
    expect(await words('စကား'), ['စကားစမြည်', 'စကားလုံးသည်']);
    expect(await hits('"စကားစမြည်"'), 1);
  });

  test('English is still stemmed', () async {
    expect(await hits('"run"'), 1);
  });

  test('the index records that it was built this way', () async {
    expect(await SentenceFtsBuilder.translationIndexCurrent(db), isTrue);
  });

  test('rebuilding the translations alone keeps the same rows', () async {
    final before = (await db.rawQuery(
            'SELECT lang, count(*) AS n FROM search_translation_unit '
            'GROUP BY lang ORDER BY lang'))
        .toList();
    await db.rawDelete(
        "DELETE FROM search_meta WHERE key = 'translation_format'");
    expect(await SentenceFtsBuilder.translationIndexCurrent(db), isFalse);
    await SentenceFtsBuilder.rebuildTranslations(db, ['en', 'my']);
    expect(await SentenceFtsBuilder.translationIndexCurrent(db), isTrue);
    final after = await db.rawQuery(
        'SELECT lang, count(*) AS n FROM search_translation_unit '
        'GROUP BY lang ORDER BY lang');
    expect(after, before);
    expect(await hits('"စကားစမြည်"'), 1);
  });
}
