@TestOn('windows || linux || mac-os')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:tipitaka_pali/services/database/sentence_fts_builder.dart';

/// Two index builds at once write the same rows twice.
///
/// Installing a language did exactly that: it closes the database and opens
/// it again, which starts the build that runs at every start, and then asks
/// for a build of its own. The second dropped the tables the first was still
/// filling, and the next insert failed on a duplicate id.
///
/// The race was there before and did not show, because the old index had no
/// unique column: it doubled its rows in silence instead of failing. So this
/// checks the outcome — one row per unit — rather than that no error is
/// thrown.
int? firstIntValue(List<Map<String, Object?>> rows) =>
    rows.isEmpty ? null : rows.first.values.first as int?;

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

    final batch = db.batch();
    for (var para = 1; para <= 60; para++) {
      batch.rawInsert(
          'INSERT INTO epi.sentences VALUES (?, ?, ?, ?, ?)',
          ['di01', para, 1, '$para', 'evaṃ me sutaṃ ekaṃ samayaṃ bhagavā '
              'sāvatthiyaṃ viharati jetavane anāthapiṇḍikassa ārāme $para']);
      batch.rawInsert('INSERT INTO ext.page_break VALUES (?,?,?,?,?,?,?)',
          ['di01', para, 1, 'mula_di_01', para, 0, 1]);
    }
    await batch.commit(noResult: true);
  });

  tearDown(() async => db.close());

  test('one row per unit, not two', () async {
    await SentenceFtsBuilder.build(db);

    final units = firstIntValue(
        await db.rawQuery('SELECT count(*) FROM search_unit'));
    final distinct = firstIntValue(
        await db.rawQuery('SELECT count(DISTINCT id) FROM search_unit'));
    expect(units, distinct);
    expect(units, greaterThan(0));
  });

  test('a rebuild replaces the index rather than adding to it', () async {
    await SentenceFtsBuilder.build(db);
    final first = firstIntValue(
        await db.rawQuery('SELECT count(*) FROM search_unit'));

    await SentenceFtsBuilder.build(db);
    final second = firstIntValue(
        await db.rawQuery('SELECT count(*) FROM search_unit'));

    expect(second, first,
        reason: 'building twice must leave one index, not two merged');
  });

  test('two builds at once would collide, which is why they are serialised',
      () async {
    // Started together, without the single-flight guard that
    // DatabaseHelper.buildSentenceFtsIfNeeded applies. One drops the table
    // the other is filling.
    Future<bool> run() async {
      try {
        await SentenceFtsBuilder.build(db);
        return false;
      } catch (_) {
        return true;
      }
    }

    final outcomes = await Future.wait([run(), run()]);
    final failed = outcomes.where((threw) => threw).length;

    // Either it threw, or it silently produced a doubled index. Both are why
    // the caller must not start a second build while one is running.
    final units = firstIntValue(
            await db.rawQuery('SELECT count(*) FROM search_unit')) ??
        0;
    final distinct = firstIntValue(
            await db.rawQuery('SELECT count(DISTINCT id) FROM search_unit')) ??
        0;
    expect(failed > 0 || units != distinct || units == 0, isTrue,
        reason: 'if concurrent builds were harmless the guard could go');
  });
}
