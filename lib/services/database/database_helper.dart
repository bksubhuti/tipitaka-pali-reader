import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tipitaka_pali/data/constants.dart';
import 'package:tipitaka_pali/services/prefs.dart';

final reNewLine = RegExp(r'\n');
final reTokenSpace = RegExp(r'[^a-zāīūṅñṭḍṇḷṃ ]');

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

    final docDirPath = await getApplicationSupportDirectory();
    dbPath = docDirPath.path;

    var path = join(dbPath, DatabaseInfo.fileName);
    Prefs.databaseDirPath = dbPath;

    // myLogger.i('opening Database ...');
    Database db = await openDatabase(
      path,
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
      },
    );
    // TODO: Remove this in future. This is just to patch the old DB to add missing columns without needing a full re-setup for users on older versions.
    // ==========================================
    // SILENT SCHEMA PATCH: ADD SORT_ORDER COLUMNS
    // This runs every time the DB opens and guarantees
    // the columns exist before the UI ever queries them.
    // ==========================================
    try {
      await db.execute(
          "ALTER TABLE books ADD COLUMN sort_order INTEGER DEFAULT 0;");
      debugPrint("SUCCESS: Added sort_order to books.");
    } catch (_) {
      // Column exists, ignore
    }

    try {
      await db.execute(
          "ALTER TABLE category ADD COLUMN sort_order INTEGER DEFAULT 0;");
      debugPrint("SUCCESS: Added sort_order to category.");
    } catch (_) {
      // Column exists, ignore
    }
    // ==========================================
    return db;
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

  Future<void> restore({
    required String tableName,
    required List<Map<String, Object?>> values,
  }) async {
    final dbInstance = await database;
    for (final value in values) {
      await dbInstance.insert(tableName, value);
    }
  }

  Future<void> buildWordList(updateMessageCallback) async {
    final frequencyMap = <String, int>{};
    final dbInstance = await database;
    final mapsOfCount = await dbInstance.rawQuery(
      'SELECT count(*) cnt FROM pages',
    );
    final int count = mapsOfCount.first['cnt'] as int;
    int start = 1;
    int batchCount = 500; // Updated batch count
    while (start < count) {
      final maps = await dbInstance.rawQuery('''
          SELECT content FROM pages
          WHERE id BETWEEN $start AND ${start + batchCount}
          ORDER by page
          ''');

      for (var element in maps) {
        var content = element['content'] as String;
        content = _cleanText(content);
        content = content.toLowerCase();
        final words = _cleanText(
          content,
        ).replaceAll(reNewLine, ' ').replaceAll(reTokenSpace, '').split(' ');
        for (var word in words) {
          word = _cleanWord(word);
          if (word.isNotEmpty) {
            if (frequencyMap.containsKey(word)) {
              frequencyMap[word] = frequencyMap[word]! + 1;
            } else {
              frequencyMap[word] = 1;
            }
          }
        }
      }
      start += batchCount;
      updateMessageCallback(
        'Processing the word list: ${(start / count * 100).round()}%',
      );
    }

    // writing to db
    await dbInstance.execute('DROP TABLE IF EXISTS words');
    await dbInstance.execute(
      'CREATE TABLE IF NOT EXISTS words (word TEXT COLLATE NOCASE, plain TEXT COLLATE NOCASE, frequency INTEGER)',
    );
    updateMessageCallback('Writing wordlist to db ...');
    final before = DateTime.now();
    final length = frequencyMap.length;
    debugPrint('wordlist count: $length');
    final wordlist = frequencyMap.entries.toList();
    var chunks = <List<MapEntry<String, int>>>[];
    int chunkSize = 10000;
    for (var i = 0; i < length; i += chunkSize) {
      chunks.add(
        wordlist.sublist(i, i + chunkSize > length ? length : i + chunkSize),
      );
    }
    int chunkIndex = 1;
    final chunkCount = chunks.length;
    for (var chunk in chunks) {
      var buffer = StringBuffer();
      buffer.write('INSERT INTO words (word, plain, frequency) VALUES ');
      for (var entry in chunk) {
        buffer.write(
          '("${entry.key}", "${_toPlain(entry.key)}", ${entry.value}), ',
        );
      }
      await dbInstance.rawInsert(
        buffer.toString().substring(0, buffer.length - 2),
      );
      updateMessageCallback(
        'Writing wordlist to db: ${((100 / chunkCount) * chunkIndex).round()}%',
      );
      chunkIndex++;
    }

    final after = DateTime.now();
    debugPrint('saving wordlist time: ${after.difference(before).inSeconds}');
  }

  Future<bool> buildBothIndexes() async {
    await buildContentIndexes();
    await buildDictionaryIndexes();
    return true;
  }

  Future<bool> buildContentIndexes() async {
    final dbInstance = await database;

    // Drop indexes if they exist
    await dbInstance.execute('DROP INDEX IF EXISTS "page_index";');
    await dbInstance.execute('DROP INDEX IF EXISTS "paragraph_index";');
    await dbInstance.execute('DROP INDEX IF EXISTS "paragraph_mapping_index";');
    await dbInstance.execute('DROP INDEX IF EXISTS "toc_index";');
    await dbInstance.execute('DROP INDEX IF EXISTS "word_index";');
    // building Index
    await dbInstance.execute(
      'CREATE INDEX IF NOT EXISTS page_index ON pages ( bookid );',
    );
    await dbInstance.execute(
      'CREATE INDEX IF NOT EXISTS paragraph_index ON paragraphs ( book_id );',
    );
    await dbInstance.execute(
      'CREATE INDEX IF NOT EXISTS paragraph_mapping_index ON paragraph_mapping ( base_page_number);',
    );
    await dbInstance.execute(
      'CREATE INDEX IF NOT EXISTS toc_index ON tocs ( book_id );',
    );
    await dbInstance.execute(
      'CREATE INDEX IF NOT EXISTS word_index ON words ( "word", "plain");',
    );

    return true;
  }

  Future<bool> buildDictionaryIndexes() async {
    final dbInstance = await database;

    // Drop indexes if they exist
    await dbInstance.execute('DROP INDEX IF EXISTS "dictionary_index";');
    await dbInstance.execute(
      'DROP INDEX IF EXISTS "dictionary_book_id_index";',
    );
    await dbInstance.execute('DROP INDEX IF EXISTS "dpd_headwords_index";');
    await dbInstance.execute('DROP INDEX IF EXISTS "dpd_index";');
    await dbInstance.execute('DROP INDEX IF EXISTS "dpd_grammar_index";');
    await dbInstance.execute('DROP INDEX IF EXISTS "dpr_stem_index";');
    await dbInstance.execute('DROP INDEX IF EXISTS "dpd_word_split_index";');
    // building Index
    await dbInstance.execute(
      'CREATE INDEX IF NOT EXISTS "dictionary_index" ON "dictionary" ("word");',
    );
    await dbInstance.execute(
      'CREATE INDEX IF NOT EXISTS "dictionary_book_id_index" ON "dictionary" ("word"	ASC,"book_id"	ASC);',
    );
    await dbInstance.execute(
      'CREATE INDEX IF NOT EXISTS "dpd_headwords_index" ON "dpd_inflections_to_headwords" ("inflection"	ASC);',
    );
    await dbInstance.execute(
      'CREATE INDEX IF NOT EXISTS "dpd_index" ON "dpd" ("word","book_id");',
    );
    await dbInstance.execute(
      'CREATE INDEX IF NOT EXISTS "dpd_grammar_index" ON "dpd_grammar" ("word");',
    );
    await dbInstance.execute(
      'CREATE INDEX IF NOT EXISTS "dpr_stem_index" ON "dpr_stem" ("word"	ASC);',
    );
    await dbInstance.execute(
      'CREATE INDEX IF NOT EXISTS "dpd_word_split_index" ON "dpd_word_split" ("word");',
    );
    await dbInstance.execute(
      'CREATE INDEX IF NOT EXISTS "sutta_shortcut_index" ON "sutta_page_shortcut" ("book_id", "start_page");',
    );

    return true;
  }

  Future<bool> buildFts(updateMessageCallback) async {
    final dbInstance = await database;
    await dbInstance.execute(
      '''CREATE VIRTUAL TABLE fts_pages USING FTS5(
    id UNINDEXED, 
    bookid UNINDEXED, 
    page UNINDEXED, 
    content, 
    paranum UNINDEXED, 
    sutta_name,
    tokenize = 'porter' 
);''',
    );

    final mapsOfCount = await dbInstance.rawQuery(
      'SELECT count(*) cnt FROM pages',
    );
    final int count = mapsOfCount.first['cnt'] as int;
    int start = 1;
    int batchCount = 500;
    while (start < count) {
      final maps = await dbInstance.rawQuery('''
          SELECT id, bookid, page, content, paranum FROM pages
          WHERE id BETWEEN $start AND ${start + batchCount}
          ORDER BY page
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
      await batch.commit(noResult: true);
      start += batchCount;
      debugPrint('finished: $start rows populating');
      int percent = ((start / count) * 100).round();

      updateMessageCallback('Finished populating: $percent% of data');
    }

    return true;
  }

  String _cleanText(String text) {
    final regexHtmlTags = RegExp(r'<[^>]*>');
    text = text.replaceAll(regexHtmlTags, '');

    text = text.replaceAll('"', '');
    text = text.replaceAll("'", '');
    return text;
  }

  String _cleanWord(String word) {
    final reToken = RegExp(r'[^a-zāīūṅñṭḍṇḷṃ]');
    final cleanWord = word.replaceAll(reToken, '');
    return cleanWord;
  }

  final variations = {
    'a': RegExp(r'ā'),
    'u': RegExp(r'ū'),
    't': RegExp(r'ṭ'),
    'n': RegExp(r'[ñṇṅ]'),
    'i': RegExp(r'ī'),
    'd': RegExp(r'ḍ'),
    'l': RegExp(r'ḷ'),
    'm': RegExp(r'[ṁṃ]'),
  };
  String _toPlain(String word) {
    var plain = word.toLowerCase().trim();
    variations.forEach((key, value) {
      plain = plain.replaceAll(value, key);
    });
    return plain;
  }
}
