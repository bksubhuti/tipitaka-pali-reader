import 'package:tipitaka_pali/business_logic/models/category.dart';
import 'package:tipitaka_pali/services/dao/catergory_dao.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';

abstract class CategoryRepository {
  late DatabaseHelper databaseProvider;
  Future<List<Category>> getCategories(String basket);
}

class CategoryDatabaseRepository implements CategoryRepository {
  final dao = CategoryDao();
  @override
  DatabaseHelper databaseProvider;
  CategoryDatabaseRepository(this.databaseProvider);

  @override
  Future<List<Category>> getCategories(String basket) async {
    if (basket != 'annya') {
      basket = 'tri';
    }
    final db = await databaseProvider.database;
    List<Map<String, dynamic>> maps = await db.query(dao.tableName,
        columns: [dao.columnID, dao.columnName],
        where: '${dao.columnBasket} = ?',
        whereArgs: [basket],
        orderBy: "sort_order ASC");
    return dao.fromList(maps);
  }
}
