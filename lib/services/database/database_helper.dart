import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tipitaka_pali/app.dart';
import 'package:tipitaka_pali/data/constants.dart';
import 'package:tipitaka_pali/services/database/legacy_data_retirement.dart';
import 'package:tipitaka_pali/services/database/sentence_data_installer.dart';
import 'package:tipitaka_pali/services/database/sentence_fts_builder.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/utils/fts_text_extractor.dart';

final reNewLine = RegExp(r'\n');
final reTokenSpace = RegExp(r'[^a-zāīūṅñṭḍṇḷṃ ]');

class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;

  static Database? _database;
  static Completer<Database>? _dbCompleter;

  Future<Database> get database async {
    if (_database != null) return _database!;

    if (_dbCompleter == null) {
      _dbCompleter = Completer<Database>();
      try {
        final db = await _initDatabase();
        _database = db;
        _dbCompleter!.complete(db);
        // Build the sentence search index once, in the background. Not
        // awaited: opening the app must not wait on it, and search stays on
        // the page index until it finishes.
        unawaited(buildSentenceFtsIfNeeded(
          onProgress: (msg) => myLogger.i(msg),
        ).then((_) => retireLegacyDataIfReady(
              onProgress: (msg) => myLogger.i(msg),
            )).then((_) => reclaimSpaceIfWorthwhile(
              onProgress: (msg) => myLogger.i(msg),
            )).catchError((Object e) {
          myLogger.e('sentence setup failed: $e');
          return false;
        }));
      } catch (e) {
        _dbCompleter!.completeError(e);
        _dbCompleter = null;
        rethrow;
      }
    }
    return _dbCompleter!.future;
  }

  // Open Assets Database
  _initDatabase() async {
    // myLogger.i('initializing Database');
    late String dbPath;

    final docDirPath = await getApplicationSupportDirectory();
    dbPath = docDirPath.path;

    var path = join(dbPath, DatabaseInfo.fileName);
    Prefs.databaseDirPath = dbPath;

    // Put the sentence databases in place before opening, so the attach below
    // finds them. Setup only runs on a fresh install, so this cannot wait for
    // it: an existing reader would never receive them.
    await SentenceDataInstaller.install(dbPath,
        onProgress: (msg) => myLogger.i(msg));

    // myLogger.i('opening Database ...');
    Database db = await openDatabase(
      path,
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
        await _attachSentenceData(db, dbPath);
      },
    );
    return db;
  }

  /// True when ePitaka's sentences and the TPR extension are both attached,
  /// so the reader can build pages from sentences instead of the `pages`
  /// table. False leaves the app exactly as it was.
  static bool sentenceDataAvailable = false;

  /// True when the paragraph-based search index has been built. Independent
  /// of [sentenceDataAvailable]: the reader can run on sentences while search
  /// still uses the old page index.
  static bool sentenceSearchAvailable = false;

  /// Language codes installed and attached, e.g. ['en', 'vi'].
  ///
  /// A language is a file named `lang_<code>.db` sitting beside the main
  /// database, holding nothing but sentence translations keyed the way
  /// ePitaka keys its sentences. Adding one is a download; removing one is
  /// deleting the file. Nothing is rebuilt either way.
  static List<String> installedLanguages = const [];

  /// Attaches `epitaka.db` and `tpr_extension.db` if they are sitting beside
  /// the main database.
  ///
  /// Deliberately quiet about failure: if either file is missing or will not
  /// open, the app carries on reading pages the way it always has. This is how
  /// the sentence-based reader is tried out without putting the existing one
  /// at risk.
  static Future<void> _attachSentenceData(Database db, String dbPath) async {
    sentenceDataAvailable = false;
    sentenceSearchAvailable = false;
    try {
      final epitaka = join(dbPath, 'epitaka.db');
      final extension = join(dbPath, 'tpr_extension.db');
      if (!File(epitaka).existsSync() || !File(extension).existsSync()) {
        myLogger.i('sentence data not present; using the pages table');
        return;
      }
      await db.execute("ATTACH DATABASE ? AS epi", [epitaka]);
      await db.execute("ATTACH DATABASE ? AS ext", [extension]);
      // Prove both are readable before letting the reader depend on them.
      await db.rawQuery('SELECT count(*) FROM epi.sentences LIMIT 1');
      await db.rawQuery('SELECT count(*) FROM ext.page_break LIMIT 1');
      sentenceDataAvailable = true;
      myLogger.i('sentence data attached; reader will build pages from it');

      // The search index is built on device, not shipped. If a previous run
      // built it, search can use it right away; otherwise it stays on the old
      // page index until the build runs.
      sentenceSearchAvailable = await SentenceFtsBuilder.isBuilt(db);
      myLogger.i('sentence search index available: $sentenceSearchAvailable');
      await _attachLanguages(db, dbPath);
    } catch (e) {
      sentenceDataAvailable = false;
      sentenceSearchAvailable = false;
      myLogger.e('could not attach sentence data: $e');
    }
  }

  /// Whether any translation is available to show alongside the Pali.
  ///
  /// Two sources, because both can be true during the change-over: a language
  /// installed as its own `lang_<code>.db`, or the old translation index
  /// inside the main database. The old one is checked second and only if it
  /// is still there, since retirement drops it and a missing table must read
  /// as "no legacy translation" rather than as an error.
  ///
  /// The reader used to ask this by counting `fts_translation_pages` and
  /// treating any failure as false, which meant that after retirement the
  /// bilingual controls quietly disappeared for someone who had a language
  /// installed.
  static Future<bool> hasTranslations() async {
    if (installedLanguages.isNotEmpty) return true;
    try {
      final db = await DatabaseHelper().database;
      final present = await db.rawQuery(
          "SELECT count(*) AS n FROM sqlite_master "
          "WHERE type='table' AND name='fts_translation_pages'");
      if ((present.first['n'] as int) == 0) return false;
      final rows = await db
          .rawQuery('SELECT count(*) AS n FROM fts_translation_pages');
      return ((rows.first['n'] as int?) ?? 0) > 0;
    } catch (_) {
      return false;
    }
  }

  /// Attaches every installed language file.
  ///
  /// One that will not open is skipped and logged rather than taking the rest
  /// down with it: a broken translation should cost that translation, not the
  /// ability to read.
  static Future<void> _attachLanguages(Database db, String dbPath) async {
    final codes = <String>[];
    try {
      final entries = Directory(dbPath).listSync();
      final names = entries
          .whereType<File>()
          .map((f) => basename(f.path))
          .where((n) => n.startsWith('lang_') && n.endsWith('.db'))
          .toList()
        ..sort();
      for (final name in names) {
        final code = name.substring(5, name.length - 3);
        if (code.isEmpty) continue;
        try {
          await db.execute("ATTACH DATABASE ? AS lang_$code",
              [join(dbPath, name)]);
          await db.rawQuery('SELECT count(*) FROM lang_$code.sentences LIMIT 1');
          codes.add(code);
        } catch (e) {
          myLogger.e('could not attach language $code: $e');
        }
      }
    } catch (e) {
      myLogger.e('could not look for language files: $e');
    }
    installedLanguages = codes;

    // A language that has just appeared is shown; one the reader switched off
    // stays off. Those look the same from the file alone, so the ones already
    // offered are remembered separately.
    //
    // This also repairs the older fault where the first-run screen wrote a
    // single language and nothing ever added to it, leaving a second install
    // on disk, attached, and invisible.
    final known = Prefs.knownLanguages;
    final fresh = codes.where((c) => !known.contains(c)).toList();
    if (fresh.isNotEmpty) {
      Prefs.knownLanguages = [...known, ...fresh];
      Prefs.activeLanguages = [
        ...Prefs.activeLanguages.where(codes.contains),
        ...fresh,
      ];
      myLogger.i('showing languages: ${Prefs.activeLanguages.join(", ")}');
    }
    myLogger.i('languages attached: ${codes.isEmpty ? "none" : codes.join(", ")}');
  }

  /// Builds the sentence-based search index if it is not there yet.
  ///
  /// Separate from attaching, because the build takes a while and wants a
  /// progress message, while attaching has to finish before the app opens.
  /// Search keeps using the old page index until this completes.
  /// The build in flight, if any.
  ///
  /// Two of them at once write the same rows twice. Installing a language
  /// does exactly that: it closes the database and opens it again, which
  /// starts the background build, and then asks for a build itself. The
  /// second one dropped the tables the first was still filling, and the
  /// insert that followed failed on a duplicate id.
  ///
  /// It was there before and did not show: the old index had no unique
  /// column, so a race doubled its rows in silence instead of failing.
  static Future<int>? _ftsBuild;

  Future<int> buildSentenceFtsIfNeeded({
    void Function(String message)? onProgress,
  }) {
    final running = _ftsBuild;
    if (running != null) return running;
    final started = _buildSentenceFts(onProgress: onProgress);
    _ftsBuild = started;
    return started.whenComplete(() {
      if (identical(_ftsBuild, started)) _ftsBuild = null;
    });
  }

  Future<int> _buildSentenceFts({
    void Function(String message)? onProgress,
  }) async {
    if (!sentenceDataAvailable) return 0;
    final db = await database;
    // Rebuild when the set of installed languages has changed, so adding or
    // removing one is reflected in search rather than silently ignored.
    final indexed = await SentenceFtsBuilder.indexedLanguages(db);
    final wanted = [...installedLanguages]..sort();
    final built = await SentenceFtsBuilder.isBuilt(db);
    if (built && indexed.join(',') == wanted.join(',')) {
      sentenceSearchAvailable = true;
      return 0;
    }
    try {
      final count = await SentenceFtsBuilder.build(db,
          languages: installedLanguages, onProgress: onProgress);
      sentenceSearchAvailable = count > 0;
      myLogger.i('sentence search index built: $count units');
      return count;
    } catch (e) {
      // A part-written index reads as a whole one and would quietly search a
      // fraction of the canon. Take it away and leave the next start to
      // build it again.
      sentenceSearchAvailable = false;
      myLogger.e('search index build failed, discarding it: $e');
      await SentenceFtsBuilder.discard(db);
      rethrow;
    }
  }

  /// Removes the page-shaped data, once the sentence data is carrying the
  /// reader, the search and the contents.
  ///
  /// Held back until the sentence search index exists, so the app is never
  /// left with neither: if the index build failed, the old one is still there
  /// to search.
  /// Gives back the space a rebuilt index or a retirement left behind.
  ///
  /// SQLite does not shrink a file when rows go; the pages are kept on a free
  /// list and reused. Replacing the search index frees several hundred
  /// megabytes that way, and without this the reader sees no change in the
  /// figure their phone reports.
  ///
  /// Only when there is enough to be worth it. VACUUM rewrites the whole
  /// database, which on this one is a gigabyte of copying, so it is not
  /// something to do on the chance of reclaiming a few pages. Retirement
  /// vacuums as its last step, so after that this finds nothing to do and
  /// returns without touching the file.
  static const _reclaimThresholdMb = 64;

  Future<bool> reclaimSpaceIfWorthwhile({
    void Function(String message)? onProgress,
  }) async {
    try {
      return await reclaimSpace(await database, onProgress: onProgress);
    } catch (e) {
      // Not worth failing a start over. The space stays on the free list and
      // is reused rather than lost.
      myLogger.e('could not reclaim space: $e');
      return false;
    }
  }

  /// The same, against a given database. Separate so it can be tested without
  /// the installed one.
  static Future<bool> reclaimSpace(
    Database db, {
    int thresholdMb = _reclaimThresholdMb,
    void Function(String message)? onProgress,
  }) async {
    final pageSize =
        Sqflite.firstIntValue(await db.rawQuery('PRAGMA page_size')) ?? 4096;
    final free =
        Sqflite.firstIntValue(await db.rawQuery('PRAGMA freelist_count')) ?? 0;
    final freeMb = free * pageSize / (1024 * 1024);
    if (freeMb < thresholdMb) return false;

    onProgress?.call('Reclaiming ${freeMb.round()} MB…');
    await db.execute('VACUUM');
    onProgress?.call('Reclaimed ${freeMb.round()} MB');
    return true;
  }

  Future<bool> retireLegacyDataIfReady({
    void Function(String message)? onProgress,
  }) async {
    if (!sentenceDataAvailable || !sentenceSearchAvailable) return false;
    final db = await database;
    if (!await LegacyDataRetirement.isPending(db)) return false;
    myLogger.i('retiring the page-shaped data');
    await LegacyDataRetirement.run(db, onProgress: onProgress);
    myLogger.i('page-shaped data retired');
    return true;
  }

  Future close() async {
    // Wait for an index build rather than closing the database under it.
    // Installing a language closes and reopens, and a build started at app
    // start may still be running.
    final building = _ftsBuild;
    if (building != null) {
      try {
        await building;
      } catch (_) {
        // Its own caller reports it; here it only has to have finished.
      }
    }
    await _database?.close();
    _database = null;
    _dbCompleter = null;
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

    // Counted from the sentences once the page text is retired. This is
    // reachable from settings, so it has to answer on either kind of install
    // rather than fail on a missing table.
    if (!await LegacyDataRetirement.isPending(dbInstance) &&
        sentenceDataAvailable) {
      await LegacyDataRetirement.rebuildWordLists(
        dbInstance,
        onProgress: (message) => updateMessageCallback(message),
      );
      return;
    }

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

  Future<bool> buildBothIndexes(
      [Function(String)? updateMessageCallback]) async {
    await buildContentIndexes(updateMessageCallback);
    await buildDictionaryIndexes(updateMessageCallback);
    return true;
  }

  Future<bool> buildContentIndexes(
      [Function(String)? updateMessageCallback]) async {
    final dbInstance = await database;

    if (updateMessageCallback != null) {
      updateMessageCallback('Dropping old content indexes...');
    }
    // Drop indexes if they exist
    await dbInstance.execute('DROP INDEX IF EXISTS "page_index";');
    await dbInstance.execute('DROP INDEX IF EXISTS "paragraph_index";');
    await dbInstance.execute('DROP INDEX IF EXISTS "paragraph_mapping_index";');
    await dbInstance.execute('DROP INDEX IF EXISTS "toc_index";');
    await dbInstance.execute('DROP INDEX IF EXISTS "word_index";');

    if (updateMessageCallback != null) {
      updateMessageCallback('Building content indexes...');
    }
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
      'DELETE FROM words WHERE rowid NOT IN (SELECT min(rowid) FROM words GROUP BY word);',
    );
    await dbInstance.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS word_unique_index ON words ( "word" );',
    );
    await dbInstance.execute(
      'CREATE INDEX IF NOT EXISTS word_plain_index ON words ( plain );',
    );

    return true;
  }

  Future<bool> buildDictionaryIndexes(
      [Function(String)? updateMessageCallback]) async {
    final dbInstance = await database;

    if (updateMessageCallback != null) {
      updateMessageCallback('Dropping old dictionary indexes...');
    }
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

    if (updateMessageCallback != null) {
      updateMessageCallback('Building dictionary indexes...');
    }
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
      '''CREATE VIRTUAL TABLE IF NOT EXISTS fts_pages USING FTS5(
    id UNINDEXED, 
    bookid UNINDEXED, 
    page UNINDEXED, 
    content, 
    paranum UNINDEXED, 
    sutta_name,
    tokenize = 'porter' 
);''',
    );

    await dbInstance.execute('DROP TABLE IF EXISTS fts_translation_pages;');
    await dbInstance.execute(
      '''CREATE VIRTUAL TABLE fts_translation_pages USING FTS5(
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
    final int totalRows = (mapsOfCount.first['cnt'] as int?) ?? 0;
    int lastId = 0;
    int batchCount = 500;
    int rowsProcessed = 0;

    while (rowsProcessed < totalRows) {
      final maps = await dbInstance.rawQuery('''
          SELECT id, bookid, page, content, paranum FROM pages
          WHERE id > $lastId
          ORDER BY id ASC
          LIMIT $batchCount
          ''');

      if (maps.isEmpty) break; // safeguard

      Batch batch = dbInstance.batch();
      for (var element in maps) {
        final rawContent = element['content'] as String;

        // 1. Extract pure Pali content for fts_pages
        final paliText = _extractPaliText(rawContent);
        final paliValue = <String, Object?>{
          'rowid': element['id'] as int,
          'id': element['id'] as int,
          'bookid': element['bookid'] as String,
          'page': element['page'] as int,
          'content': paliText,
          'paranum': element['paranum'] as String,
        };
        batch.insert('fts_pages', paliValue,
            conflictAlgorithm: ConflictAlgorithm.replace);

        // 2. Extract translation content for fts_translation_pages (if present)
        final translationText = _extractTranslationText(rawContent);
        if (translationText.isNotEmpty) {
          final transValue = <String, Object?>{
            'rowid': element['id'] as int,
            'id': element['id'] as int,
            'bookid': element['bookid'] as String,
            'page': element['page'] as int,
            'content': translationText,
            'paranum': element['paranum'] as String,
          };
          batch.insert('fts_translation_pages', transValue,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }

        lastId = element['id'] as int;
      }
      await batch.commit(noResult: true);

      rowsProcessed += maps.length;
      debugPrint('finished: $rowsProcessed rows populating');

      int percent = ((rowsProcessed / totalRows) * 100).round();
      if (percent > 100) percent = 100;

      if (updateMessageCallback != null) {
        updateMessageCallback('Finished populating: $percent% of data');
      }
    }
    return true;
  }

  String _extractPaliText(String html) =>
      FtsTextExtractor.extractPaliText(html);

  String _extractTranslationText(String html) =>
      FtsTextExtractor.extractTranslationText(html);

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
