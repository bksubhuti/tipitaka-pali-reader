@TestOn('windows || linux || mac-os')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:tipitaka_pali/services/database/database_helper.dart';

/// Replacing the search index frees several hundred megabytes, but SQLite
/// keeps freed pages on a free list rather than shortening the file. Without
/// a vacuum the reader sees no change in the size their phone reports.
void main() {
  late Directory dir;
  late String path;
  late Database db;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('reclaim');
    path = '${dir.path}/test.db';
    db = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(singleInstance: false));
    await db.execute('CREATE TABLE big (id INTEGER PRIMARY KEY, blob TEXT)');
    final batch = db.batch();
    final filler = 'x' * 4000;
    for (var i = 0; i < 3000; i++) {
      batch.insert('big', {'blob': filler});
    }
    await batch.commit(noResult: true);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('space freed by a rebuild is given back', () async {
    final before = File(path).lengthSync();
    await db.execute('DELETE FROM big');

    final stillLarge = File(path).lengthSync();
    expect(stillLarge, greaterThanOrEqualTo(before - 4096),
        reason: 'SQLite should not have shrunk the file on its own');

    final reclaimed =
        await DatabaseHelper.reclaimSpace(db, thresholdMb: 1);
    expect(reclaimed, isTrue);
    expect(File(path).lengthSync(), lessThan(before ~/ 2));
  });

  test('a database with little to give back is left alone', () async {
    final before = File(path).lengthSync();
    // Nothing deleted, so the free list is small.
    final reclaimed = await DatabaseHelper.reclaimSpace(db, thresholdMb: 64);
    expect(reclaimed, isFalse,
        reason: 'VACUUM rewrites the whole file; it is not worth doing on the '
            'chance of reclaiming a few pages');
    expect(File(path).lengthSync(), before);
  });
}
