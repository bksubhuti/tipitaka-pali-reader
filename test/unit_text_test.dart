@TestOn('windows || linux || mac-os')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:tipitaka_pali/services/database/unit_text.dart';

/// The search indexes no longer store the text they matched on, so every
/// snippet, every highlight and every page number a result opens on is worked
/// out from text rebuilt here.
///
/// If that rebuild differs from what was indexed by so much as a space, the
/// offsets are wrong and results open on the wrong page — the same failure we
/// had before, which no summary number showed. So this checks the rebuilt
/// text against the index itself rather than against a fixture.
void main() {
  const dbDir =
      r'C:\Users\Vasil\AppData\Roaming\com.paauk\tipitaka_pali_reader';

  late Database db;
  var haveIndex = false;

  setUpAll(() async {
    sqfliteFfiInit();
    if (!File('$dbDir\\tipitaka_pali.db').existsSync()) return;
    db = await databaseFactoryFfi.openDatabase(
      '$dbDir\\tipitaka_pali.db',
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    await db.execute("ATTACH DATABASE '$dbDir\\epitaka.db' AS epi");
    await db.execute("ATTACH DATABASE '$dbDir\\tpr_extension.db' AS ext");
    final rows = await db.rawQuery("SELECT count(*) AS n FROM sqlite_master "
        "WHERE type='table' AND name='search_unit'");
    haveIndex = (rows.first['n'] as int) > 0;
  });

  tearDownAll(() async {
    if (haveIndex) await db.close();
  });

  test('a unit rebuilds to text the index can be searched for', () async {
    if (!haveIndex) {
      markTestSkipped('no contentless index built on this machine');
      return;
    }

    // Spread across the canon rather than the first few, which are all the
    // same opening formula.
    final units = await db.rawQuery(
        'SELECT id, epi_book, start_para, end_para FROM search_unit '
        'WHERE id % 97 = 0 LIMIT 120');
    expect(units, isNotEmpty);

    var checked = 0;
    for (final unit in units) {
      final text = await UnitText.pali(db,
          epiBook: unit['epi_book'] as String,
          startPara: unit['start_para'] as int,
          endPara: unit['end_para'] as int);
      expect(text, isNotEmpty,
          reason: 'unit ${unit['id']} rebuilt to nothing, so every result in '
              'it would lose its snippet and open on the wrong page');

      // A run of words out of the middle of the unit must find that same
      // unit through the index. This is the round trip: if the rebuild and
      // the index disagreed about the text, it would not.
      //
      // The run has to be contiguous. Picking words out of the text and
      // joining them makes a phrase that was never written, which finds
      // nothing and says nothing about whether the rebuild is right.
      final words = text.split(' ');
      if (words.length < 20) continue;
      final phrase = words.sublist(10, 14).join(' ').replaceAll("'", "''");
      if (phrase.contains('"')) continue;
      // Asked of this unit alone. The canon repeats its formulas, so a
      // phrase can match hundreds of units and the one we want falls outside
      // any limit; that would be a fact about the canon, not about the
      // rebuild.
      final hits = await db.rawQuery(
        'SELECT rowid FROM fts_unit '
        "WHERE fts_unit MATCH '\"$phrase\"' AND rowid = ?",
        [unit['id']],
      );
      expect(hits, isNotEmpty,
          reason: 'a phrase taken out of the rebuilt text of unit '
              '${unit['id']} did not match that unit in the index, so the '
              'rebuild and the index disagree about what the text is');
      checked++;
    }
    expect(checked, greaterThan(50), reason: 'too few units actually tested');
  });

  test('the index keeps no copy of the text', () async {
    if (!haveIndex) {
      markTestSkipped('no contentless index built on this machine');
      return;
    }
    // A contentless FTS5 table answers null for the column it does not keep.
    // That null is the point of the change: it is what 584 MB looks like.
    final rows = await db.rawQuery('SELECT content FROM fts_unit LIMIT 1');
    expect(rows.first['content'], isNull);
  });

  test('every unit knows which sentences it came from', () async {
    if (!haveIndex) {
      markTestSkipped('no contentless index built on this machine');
      return;
    }
    final bad = await db.rawQuery(
        'SELECT count(*) AS n FROM search_unit '
        'WHERE epi_book IS NULL OR epi_book = ? '
        '   OR end_para < start_para',
        ['']);
    expect(bad.first['n'], 0,
        reason: 'a unit with no range cannot be rebuilt at all');
  });
}
