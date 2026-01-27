import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tipitaka_pali/business_logic/models/folder.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';

abstract class FolderRepository {
  Future<List<Folder>> fetchFolders();
  Future<void> insertFolder(String folderName, int parent_folder_id);
  Future<int> updateFolder(Folder folder);
  Future<int> deleteFolder(int folderId);
  Future<int> updateFolderParentId(int itemId, int selectedFolderId);
  Future<List<Folder>> fetchFoldersByParentId(int parentId);
  Future<List<Folder>> fetchAllSubFolders(int folderId);
}

class FolderDatabaseRepository extends FolderRepository {
  final DatabaseHelper _databaseHelper;

  FolderDatabaseRepository(this._databaseHelper);

  @override
  Future<List<Folder>> fetchFolders() async {
    final db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps = await db.query('folder');

    return List<Folder>.from(maps.map((folder) => Folder.fromJson(folder)));
  }

  @override
  Future<List<Folder>> fetchFoldersByParentId(int parentId) async {
    final db = await _databaseHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'folder',
      where: 'parent_folder_id = ?',
      whereArgs: [parentId],
    );
    return List<Folder>.from(maps.map((folder) => Folder.fromJson(folder)));
  }

  Future<List<Folder>> fetchAllFolders({int? exclusionId}) async {
    final db = await _databaseHelper.database;
    String? whereClause = exclusionId != null ? 'id != ?' : null; // Adjusted
    List<dynamic> whereArgs = exclusionId != null ? [exclusionId] : [];

    final List<Map<String, dynamic>> maps = await db.query(
      'folder', // Ensure your table name is correct; it should match your CREATE TABLE statement
      where: whereClause,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
    );
    return List<Folder>.from(maps.map((folder) => Folder.fromJson(folder)));
  }

  @override
  Future<List<Folder>> fetchAllSubFolders(int folderId) async {
    final db = await _databaseHelper.database;
    String whereClause = 'parent_folder_id = ?'; // Adjusted

    final List<Map<String, dynamic>> maps = await db.query(
      'folder', // Ensure your table name is correct; it should match your CREATE TABLE statement
      where: whereClause,
      whereArgs: [folderId],
    );
    return List<Folder>.from(maps.map((folder) => Folder.fromJson(folder)));
  }

  @override
  Future<int> insertFolder(String folderName, int parentFolderId) async {
    final db = await _databaseHelper.database;
    int id = await db.insert(
      'folder',
      {
        'name': folderName,
        'parent_folder_id':
            parentFolderId, // Use the correct column name as per your schema
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return id; // Return the ID of the newly inserted row
  }

  @override
  Future<int> updateFolder(Folder folder) async {
    final db = await _databaseHelper.database;
    return await db.update(
      'folder',
      folder.toJson(),
      where: 'id = ?',
      whereArgs: [folder.id],
    );
  }

  @override
  Future<int> deleteFolder(int folderId) async {
    final db = await _databaseHelper.database;
    return await db.delete(
      'folder',
      where: 'id = ?',
      whereArgs: [folderId],
    );
  }

  @override
  Future<int> updateFolderParentId(int itemId, int selectedFolderId) async {
    final db = await _databaseHelper.database;
    int result = await db.update(
      'folder',
      {'parent_folder_id': selectedFolderId}, // Column(s) to update
      where: 'id = ?', // Identifying the row to update
      whereArgs: [itemId], // Value for the `where` clause
    );
    return result; // Number of rows affected (should be 1 if a row was updated)
  }
}
