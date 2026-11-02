@TestOn('windows || linux || mac-os')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:tipitaka_pali/services/database/data_patches.dart';

/// The page-break patch moves only the wrong first page of a second volume,
/// and leaves a database that is already right untouched.
void main() {
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await db.execute("ATTACH DATABASE ':memory:' AS ext");
    await db.execute('CREATE TABLE ext.page_break (book_id TEXT, '
        'para_id INTEGER, line_id INTEGER, tpr_book TEXT, tpr_page INTEGER, '
        'word_index INTEGER, exact INTEGER)');
    for (final row in [
      ['Vin-vn-t', 1, 1, 'annya_vi_10', 1, 0], // first volume, page 1
      ['Vin-vn-t', 1, 1, 'annya_vi_11', 1, 0], // second volume: wrong
      ['Vin-vn-t', 2423, 2, 'annya_vi_11', 2, 9],
    ]) {
      await db.rawInsert(
          'INSERT INTO ext.page_break VALUES (?, ?, ?, ?, ?, ?, 1)', row);
    }
  });

  tearDown(() => db.close());

  Future<List<Map<String, Object?>>> firstPages() => db.rawQuery(
      'SELECT tpr_book, para_id, line_id, word_index FROM ext.page_break '
      'WHERE tpr_page = 1 ORDER BY tpr_book');

  test('moves the second volume to its own beginning', () async {
    await DataPatches.apply(db);
    expect(await firstPages(), [
      {'tpr_book': 'annya_vi_10', 'para_id': 1, 'line_id': 1, 'word_index': 0},
      {
        'tpr_book': 'annya_vi_11',
        'para_id': 2417,
        'line_id': 1,
        'word_index': 0
      },
    ]);
    expect(DataPatches.changedBooks, ['Vin-vn-t']);
  });

  test('changes nothing the second time, or on fixed data', () async {
    await DataPatches.apply(db);
    await DataPatches.apply(db);
    expect(DataPatches.changedBooks, isEmpty);
  });
}
