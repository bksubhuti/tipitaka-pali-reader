import 'package:tipitaka_pali/services/dao/book_dao.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/business_logic/models/book.dart';

abstract class BookRepository {
  Future<List<Book>> getBooks(String basket, String category);
  Future<List<Book>> getAllBooks();
  Future<String> getName(String id);
  Future<int> getFirstPage(String id);
  Future<int> getLastPage(String id);
}

class BookDatabaseRepository implements BookRepository {
  final dao = BookDao();
  final DatabaseHelper databaseProvider;
  BookDatabaseRepository(this.databaseProvider);

  @override
  Future<List<Book>> getBooks(String basket, String category) async {
    final db = await databaseProvider.database;
    List<Map<String, dynamic>> maps = await db.query(dao.tableName,
        columns: [dao.columnID, dao.columnName],
        where: '${dao.columnBasket} = ? AND ${dao.colunmnCategory} = ?',
        whereArgs: [basket, category],
        orderBy: "sort_order ASC");
    return dao.fromList(maps);
  }

  @override
  Future<List<Book>> getAllBooks() async {
    final db = await databaseProvider.database;
    List<Map<String, dynamic>> maps = await db.query(dao.tableName,
        columns: [dao.columnID, dao.columnName], orderBy: "sort_order ASC");
    return dao.fromList(maps);
  }

  @override
  Future<String> getName(String id) async {
    final db = await databaseProvider.database;
    List<Map> maps = await db.query(dao.tableName,
        columns: [dao.columnName],
        where: '${dao.columnID} = ?',
        whereArgs: [id]);
    return maps.first[dao.columnName];
  }

  @override
  Future<int> getFirstPage(String id) async {
    final db = await databaseProvider.database;
    List<Map> maps = await db.query(dao.tableName,
        columns: [dao.columnFirstPage],
        where: '${dao.columnID} = ?',
        whereArgs: [id]);
    return maps.first[dao.columnFirstPage];
  }

  @override
  Future<int> getLastPage(String id) async {
    final db = await databaseProvider.database;
    List<Map> maps = await db.query(dao.tableName,
        columns: [dao.columnLastPage],
        where: '${dao.columnID} = ?',
        whereArgs: [id]);
    return maps.first[dao.columnLastPage];
  }
}
