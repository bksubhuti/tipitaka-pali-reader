import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tipitaka_pali/business_logic/models/bookmark.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';

abstract class BookmarkRepository {
  Future<int> insert(Bookmark bookmark);

  Future<int> deleteBookmark(int bookmarkID);

  Future<int> deleteAll();

  Future<List<Bookmark>> getAllBookmark();
  Future<List<Bookmark>> getBookmarks({required String bookID});
  Future<List<Bookmark>> getBookmarksAfter(String lastSyncDate);
  Future<int> updateBookmarkFolder(int bookmarkId, int folderId);
  Future<int> updateBookmarkName(Bookmark bookmark);
}

class BookmarkDatabaseRepository extends BookmarkRepository {
  BookmarkDatabaseRepository(this._databaseHelper); //, this.dao);
  final DatabaseHelper _databaseHelper;
  //final BookmarkDao dao;

  @override
  Future<int> insert(Bookmark bookmark) async {
    final db = await _databaseHelper.database;
    final Map<String, dynamic> bookmarkData = {
      'book_id': bookmark.bookID,
      'page_number': bookmark.pageNumber,
      'note': bookmark.note,
      'selected_text': bookmark.selectedText,
      'name': bookmark.name,
      'folder_id': bookmark.folderId, // Use -1 or another value for default
      // Do not include 'id' here as SQLite will auto-increment it
    };

    // Perform the insert operation
    int id = await db.insert(
      'bookmark',
      bookmarkData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // The 'id' returned here is the auto-incremented ID assigned by SQLite
    return id; // Return the auto-generated id to the caller if needed
  }

  @override
  Future<int> deleteBookmark(int bookmarkID) async {
    final db = await _databaseHelper.database;
    String sql = '''
         Delete from bookmark 
         Where id = $bookmarkID
         ''';
    return await db.rawDelete(sql);
  }

  @override
  Future<int> deleteAll() async {
    final db = await _databaseHelper.database;
    String sql = '''
         Delete from bookmark 
         ''';
    return await db.rawDelete(sql);
  }

  @override
  Future<List<Bookmark>> getAllBookmark() async {
    final db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps =
        await db.query('bookmark'); // Using the query helper method

    List<Bookmark> bookmarks = maps.map((x) => Bookmark.fromJson(x)).toList();
    return bookmarks;
  }

  Future<List<Bookmark>> fetchBookmarksByFolderId(int folderId) async {
    final db = await _databaseHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'bookmark',
      where: 'folder_id = ?',
      whereArgs: [folderId],
      orderBy: 'name',
    );
    return List<Bookmark>.from(
        maps.map((bookmark) => Bookmark.fromJson(bookmark)));
  }

  @override
  Future<List<Bookmark>> getBookmarks({required String bookID}) async {
    final db = await _databaseHelper.database;
    List<Map<String, dynamic>> maps =
        await db.query('bookmark', where: 'book_id = ?', whereArgs: [bookID]);
    List<Bookmark> bookmarks = maps.map((x) => Bookmark.fromJson(x)).toList();
    return bookmarks;
  }

  @override
  Future<List<Bookmark>> getBookmarksAfter(String lastSyncDate) async {
    final db = await _databaseHelper.database;
    String sql = '''
      SELECT * 
      FROM bookmark
      WHERE sync_date < "$lastSyncDate" 
      ''';
    List<Map<String, dynamic>> maps = await db.rawQuery(sql);
    return maps.map((entry) => Bookmark.fromJson(entry)).toList();
  }

  @override
  Future<int> updateBookmarkFolder(int bookmarkId, int folderId) async {
    final db = await _databaseHelper.database;
    return await db.update(
      'bookmark',
      {'folder_id': folderId},
      where: 'id = ?',
      whereArgs: [bookmarkId],
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<int> updateBookmarkName(Bookmark bookmark) async {
    final db = await _databaseHelper.database;
    return await db.update(
      'bookmark',
      {'note': bookmark.note},
      where: 'id = ?',
      whereArgs: [bookmark.id],
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
