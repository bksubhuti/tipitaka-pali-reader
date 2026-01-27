import 'package:sqflite_common/utils/utils.dart' as Sqflite;
import 'package:tipitaka_pali/services/database/database_helper.dart';

import '../../business_logic/models/search_history.dart';

abstract class SearchHistoryRepository {
  Future<int> insert(String word);

  Future<int> delete(String word);

  Future<void> deleteAll();

  Future<List<SearchHistory>> getAll();

  Future<int> getWordCount();
}

class SearchHistoryDatabaseRepository implements SearchHistoryRepository {
  SearchHistoryDatabaseRepository({required this.dbh});
  DatabaseHelper dbh;

  final _historyTable = 'search_history';
  final _columnWord = 'word';

  @override
  Future<int> insert(String word) async {
    final db = await dbh.database;
    // delete first if exists
    await db
        .delete(_historyTable, where: '$_columnWord = ?', whereArgs: [word]);

    return await db.insert(
      _historyTable,
      SearchHistory(word: word, dateTime: DateTime.now()).toMap(),
    );
  }

  @override
  Future<int> delete(String word) async {
    final db = await dbh.database;
    return await db
        .delete(_historyTable, where: '$_columnWord = ?', whereArgs: [word]);
  }

  @override
  Future<void> deleteAll() async {
    final db = await dbh.database;
    await db.delete(_historyTable);
  }

  @override
  Future<List<SearchHistory>> getAll() async {
    final db = await dbh.database;
    final maps = await db.query(
      _historyTable,
    );
    return maps.map((entry) => SearchHistory.fromMap(entry)).toList();
  }

  @override
  Future<int> getWordCount() async {
    final db = await dbh.database;

    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM words'),
    );
    //null check
    return count ?? -1;
  }
}
