@TestOn('windows || linux || mac-os')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:tipitaka_pali/services/database/sentence_fts_builder.dart';

/// Installing a language indexes that language alone, against the units the
/// Pali index already has, instead of rebuilding everything.
///
/// The risk is that a language indexed this way differs from one indexed by
/// a full build, so a search finds it in one install and not another. These
/// check the outcome against the full build rather than only that rows exist.
void main() {
  late Database db;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await db.execute("ATTACH DATABASE ':memory:' AS epi");
    await db.execute("ATTACH DATABASE ':memory:' AS ext");
    await db.execute("ATTACH DATABASE ':memory:' AS lang_en");
    await db.execute("ATTACH DATABASE ':memory:' AS lang_ru");
    await db.execute('CREATE TABLE epi.sentences (book_id TEXT, '
        'para_id INTEGER, line_id INTEGER, vripara TEXT, pali TEXT)');
    await db.execute('CREATE TABLE ext.page_break (book_id TEXT, '
        'para_id INTEGER, line_id INTEGER, tpr_book TEXT, tpr_page INTEGER, '
        'word_index INTEGER, exact INTEGER)');
    for (final code in ['en', 'ru']) {
      await db.execute('CREATE TABLE lang_$code.sentences (book_id TEXT, '
          'para_id INTEGER, line_id INTEGER, translation TEXT)');
    }

    final batch = db.batch();
    for (final book in ['di01', 'ma01']) {
      for (var para = 1; para <= 40; para++) {
        for (var line = 1; line <= 2; line++) {
          batch.rawInsert('INSERT INTO epi.sentences VALUES (?, ?, ?, ?, ?)', [
            book, para, line, '$para',
            'evaṃ me sutaṃ ekaṃ samayaṃ bhagavā sāvatthiyaṃ viharati $para'
          ]);
          batch.rawInsert('INSERT INTO lang_en.sentences VALUES (?, ?, ?, ?)',
              [book, para, line, 'Thus have I heard $book $para $line']);
          // Russian has gaps, as real translations do.
          if (para % 3 != 0) {
            batch.rawInsert(
                'INSERT INTO lang_ru.sentences VALUES (?, ?, ?, ?)',
                [book, para, line, 'Так я слышал $book $para $line']);
          }
        }
        batch.rawInsert('INSERT INTO ext.page_break VALUES (?,?,?,?,?,?,?)',
            [book, para, 1, 'mula_$book', para, 0, 1]);
      }
    }
    await batch.commit(noResult: true);
  });

  tearDown(() async => db.close());

  Future<Map<int, int>> unitsPerLanguage(String lang) async {
    final rows = await db.rawQuery(
        'SELECT unit_id, count(*) AS n FROM search_translation_unit '
        'WHERE lang = ? GROUP BY unit_id',
        [lang]);
    return {for (final r in rows) r['unit_id'] as int: r['n'] as int};
  }

  Future<List<int>> hits(String lang, String query) async {
    final rows = await db.rawQuery(
        'SELECT t.unit_id FROM fts_translation_unit f '
        'JOIN search_translation_unit t ON t.rowid_ = f.rowid '
        'WHERE fts_translation_unit MATCH ? AND t.lang = ? ORDER BY t.unit_id',
        [query, lang]);
    return rows.map((r) => r['unit_id'] as int).toList();
  }

  test('a language added later matches one indexed in a full build',
      () async {
    await SentenceFtsBuilder.build(db, languages: ['en', 'ru']);
    final fullEn = await unitsPerLanguage('en');
    final fullRu = await unitsPerLanguage('ru');
    final fullHits = await hits('ru', '"слышал ma01 17"');

    await SentenceFtsBuilder.build(db, languages: ['en']);
    expect(await unitsPerLanguage('ru'), isEmpty);
    await SentenceFtsBuilder.addLanguage(db, 'ru');

    expect(await unitsPerLanguage('ru'), fullRu);
    expect(await unitsPerLanguage('en'), fullEn, reason: 'English untouched');
    expect(await hits('ru', '"слышал ma01 17"'), fullHits);
    expect(fullHits, isNotEmpty);
    expect(await SentenceFtsBuilder.indexedLanguages(db), ['en', 'ru']);
  });

  test('adding the same language twice does not double it', () async {
    await SentenceFtsBuilder.build(db, languages: ['en']);
    await SentenceFtsBuilder.addLanguage(db, 'ru');
    final once = await unitsPerLanguage('ru');
    await SentenceFtsBuilder.addLanguage(db, 'ru');
    expect(await unitsPerLanguage('ru'), once);
    expect(once.values.every((n) => n == 1), isTrue);
  });

  test('removing a language leaves the others searchable', () async {
    await SentenceFtsBuilder.build(db, languages: ['en', 'ru']);
    final pali = (await db.rawQuery('SELECT count(*) AS n FROM search_unit'))
        .first['n'];
    final en = await hits('en', '"heard di01 5"');

    await SentenceFtsBuilder.rebuildTranslations(db, ['en']);

    expect(await unitsPerLanguage('ru'), isEmpty);
    expect(await hits('en', '"heard di01 5"'), en);
    expect(en, isNotEmpty);
    expect(
        (await db.rawQuery('SELECT count(*) AS n FROM search_unit'))
            .first['n'],
        pali,
        reason: 'the Pali index is not rebuilt');
    expect(await SentenceFtsBuilder.indexedLanguages(db), ['en']);
    expect(await SentenceFtsBuilder.isBuilt(db), isTrue);
  });
}
