import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tipitaka_pali/business_logic/models/recent.dart';
import 'package:tipitaka_pali/services/dao/recent_dao.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';

/// Rises with every entry saved, so a Recent list already on screen reads
/// itself again. It read once, when first shown, and the side panel keeps it
/// alive, so a heading opened from the tree or the contents never appeared.
final ValueNotifier<int> recentChanges = ValueNotifier(0);

abstract class RecentRepository {
  Future<int> insertOrReplace(Recent recent);

  Future<int> delete(Recent recent);

  Future<int> deleteAll();

  Future<List<Recent>> getRecents();
}

class RecentDatabaseRepository implements RecentRepository {
  RecentDatabaseRepository(this.databaseProvider, this.dao);
  DatabaseHelper databaseProvider;
  final RecentDao dao;

  @override
  Future<int> insertOrReplace(Recent recent) async {
    final db = await databaseProvider.database;
    // var result = await db.update(dao.tableName, dao.toMap(recent),
    //     where: '${dao.columnBookId} = ?', whereArgs: [recent.bookID]);
    // print('update result: $result');
    // if (result == 0) {
    //   result = await db.insert(dao.tableName, dao.toMap(recent));
    // }

    var result = await db.delete(dao.tableRecent,
        where: '${dao.columnBookId} = ?', whereArgs: [recent.bookID]);
    result = await db.insert(dao.tableRecent, dao.toMap(recent),
        conflictAlgorithm: ConflictAlgorithm.ignore);
    recentChanges.value++;

    return result;
  }

  @override
  Future<int> delete(Recent recent) async {
    final db = await databaseProvider.database;
    return await db.delete(dao.tableRecent,
        where: '${dao.columnBookId} = ?', whereArgs: [recent.bookID]);
  }

  @override
  Future<int> deleteAll() async {
    final db = await databaseProvider.database;
    return await db.delete(dao.tableRecent);
  }

  @override
  Future<List<Recent>> getRecents() async {
    final db = await databaseProvider.database;
    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT ${dao.columnBookId}, ${dao.columnPageNumber}, ${dao.columnName}
      FROM ${dao.tableRecent}
      INNER JOIN ${dao.tableBooks} ON ${dao.tableBooks}.${dao.columnID} = ${dao.tableRecent}.${dao.columnBookId}
      ''');
    return dao.fromList(maps).reversed.toList();
  }
}
