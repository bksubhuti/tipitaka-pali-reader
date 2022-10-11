import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tipitaka_pali/data/constants.dart';
import 'package:tipitaka_pali/services/prefs.dart';

class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;

  static Database? _database;
  Future<Database> get database async {
    if (_database != null) return _database!;
    // lazily instantiate the db the first time it is accessed
    _database = await _initDatabase();
    return _database!;
  }

// Open Assets Database
  _initDatabase() async {
    // myLogger.i('initializing Database');
    late String dbPath;

    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      dbPath = await getDatabasesPath();
    }
    if (Platform.isLinux || Platform.isWindows) {
      final docDirPath = await getApplicationSupportDirectory();
      dbPath = docDirPath.path;
    }
    var path = join(dbPath, DatabaseInfo.fileName);
    Prefs.databaseDirPath = dbPath;

    // myLogger.i('opening Database ...');
    return await openDatabase(path);
  }

  Future close() async {
    await _database?.close();
    _database = null;
  }

  Future<List<Map<String, Object?>>> backup({required String tableName}) async {
    final dbInstance = await database;
    final maps = await dbInstance.query(tableName);
    // print('maps: ${maps.length}');
    return maps;
  }

  // Future<List<Map<String, Object?>>> backupBookmarks() async {
  //   final dbInstance = await database;
  //   final maps = await dbInstance
  //       .query('bookmark', columns: <String>['book_id', 'page_number']);
  //   return maps;
  // }

  // Future<List<Map<String, Object?>>> backupDictionary() async {
  //   final dbInstance = await database;
  //   final maps = await dbInstance.query('dictionary_books',
  //       columns: <String>['id', 'name', 'user_order', 'user_choice']);
  //   return maps;
  // }

  Future<void> deleteDictionaryData() async {
    final dbInstance = await database;
    await dbInstance.delete('dictionary_books');
  }

  Future<void> restore(
      {required String tableName,
      required List<Map<String, Object?>> values}) async {
    final dbInstance = await database;
    for (final value in values) {
      await dbInstance.insert(tableName, value);
    }
  }

  Future<bool> buildIndex() async {
    final dbInstance = await database;
    // building Index
    await dbInstance.execute(
        'CREATE INDEX IF NOT EXISTS "dictionary_index" ON "dictionary" ("word");');
    await dbInstance.execute(
        'CREATE INDEX IF NOT EXISTS "dictionary_book_id_index" ON "dictionary" ("word"	ASC,"book_id"	ASC);');
    await dbInstance.execute(
        'CREATE INDEX IF NOT EXISTS "dpd_headwords_index" ON "dpd_inflections_to_headwords" ("inflection"	ASC);');
    await dbInstance.execute(
        'CREATE INDEX IF NOT EXISTS "dpd_index" ON "dpd" ("word","book_id");');
    await dbInstance.execute(
        'CREATE INDEX IF NOT EXISTS "dpr_stem_index" ON "dpr_stem" ("word"	ASC);');
    await dbInstance.execute(
        'CREATE INDEX IF NOT EXISTS "dpr_breakup_index" ON "dpr_breakup" ("word");');
    await dbInstance
        .execute('CREATE INDEX IF NOT EXISTS page_index ON pages ( bookid );');
    await dbInstance.execute(
        'CREATE INDEX IF NOT EXISTS paragraph_index ON paragraphs ( book_id );');
    await dbInstance.execute(
        'CREATE INDEX IF NOT EXISTS paragraph_mapping_index ON paragraph_mapping ( base_page_number);');
    await dbInstance
        .execute('CREATE INDEX IF NOT EXISTS toc_index ON tocs ( book_id );');
    await dbInstance.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS word_index ON words ( word );');

    return true;
  }

  Future<bool> buildFts(updateMessageCallback) async {
    final dbInstance = await database;
    await dbInstance
        .execute('''CREATE VIRTUAL TABLE IF NOT EXISTS fts_pages USING FTS4
         (id, bookid, page, content, paranum)''');

    final mapsOfCount =
        await dbInstance.rawQuery('SELECT count(*) cnt FROM pages');
    final int count = mapsOfCount.first['cnt'] as int;
    int start = 1;
    int batchCount = 500;
    while (start < count) {
      final maps = await dbInstance.rawQuery('''
          SELECT id, bookid, page, content, paranum FROM pages
          WHERE id BETWEEN $start AND ${start + batchCount}
          ''');

      Batch batch = dbInstance.batch();
      for (var element in maps) {
        // before populating to fts, need to remove html tag
        final value = <String, Object?>{
          'id': element['id'] as int,
          'bookid': element['bookid'] as String,
          'page': element['page'] as int,
          'content': _cleanText(element['content'] as String),
          'paranum': element['paranum'] as String,
        };
        batch.insert('fts_pages', value);
      }
      await batch.commit();
      start += batchCount;
      debugPrint('finished: $start rows populating');
      int percent = ((start / count) * 100).round();

      updateMessageCallback('Finished populating: $percent% of data');
    }

    return true;
  }

  String _cleanText(String text) {
    final regexHtmlTags = RegExp(r'<[^>]*>');
    return text.replaceAll(regexHtmlTags, '');
  }
}
