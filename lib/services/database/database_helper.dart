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
import 'package:tipitaka_pali/services/get_database_status.dart';
import 'package:tipitaka_pali/services/language_installer.dart';
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
        // Not while setup is running. Setup opens and closes the database
        // several times, and this chain reopens it whenever it needs it, so
        // starting it here left work running against a handle setup had
        // closed. Setup does these steps itself, in order, when it is done.
        //
        // Nor while setup is still to come. Something can open the database
        // at start before setup has begun (a link opening the app can), and
        // on a device with the sentence data that started an index build on
        // the database setup was about to replace, which setup then waited
        // out.
        if (!suspendBackgroundSetup &&
            getDatabaseStatus() == DatabaseStatus.uptoDate) {
          _startBackgroundSetup();
        }
      } catch (e) {
        _dbCompleter!.completeError(e);
        _dbCompleter = null;
        rethrow;
      }
    }
    return _dbCompleter!.future;
  }

  /// True while the initial setup is copying and building.
  static bool suspendBackgroundSetup = false;

  /// Builds the index, retires the old page data and gives back the space, in
  /// that order, without holding up the screen.
  ///
  /// [onProgress] also receives each step's messages, for a screen that is
  /// waiting on them.
  static void _startBackgroundSetup(
      {void Function(String message)? onProgress}) {
    final helper = DatabaseHelper();
    void report(String msg) {
      myLogger.i(msg);
      onProgress?.call(msg);
    }

    _setupChain = helper.buildSentenceFtsIfNeeded(
          onProgress: report,
    ).then((_) => helper.retireLegacyDataIfReady(
          onProgress: report,
        )).then((_) => helper.updateTranslationWordLists(
          onProgress: report,
        )).then((_) => helper.reclaimSpaceIfWorthwhile(
          onProgress: report,
        )).catchError((Object e) {
      myLogger.e('sentence setup failed: $e');
      return false;
    });
    unawaited(_setupChain!);
  }

  /// Runs the steps setup skipped, once it has finished with the database.
  ///
  /// Setup waits on these with its screen up, so [onProgress] lets it show
  /// what they are doing. Reported only to the log, the screen sat on its
  /// last message while the word lists were rebuilt and the space reclaimed.
  static Future<void> runBackgroundSetupNow(
      {void Function(String message)? onProgress}) async {
    suspendBackgroundSetup = false;
    _startBackgroundSetup(onProgress: onProgress);
    await _setupChain;
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
      await _ensureSentenceIndexes(db);
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

  /// The indexes the sentence data is read through, built here rather than
  /// shipped.
  ///
  /// They cost 45 MB in the file and 12 MB in the download, and SQLite can
  /// make them in a few seconds from data already on the device. What they
  /// cannot be is absent: every page the reader opens looks sentences up by
  /// book and paragraph, and without `idx_sentence` that is a scan of more
  /// than a million rows each time.
  ///
  /// Built once. Afterwards this is four cheap lookups against sqlite_master.
  static const _sentenceIndexes = {
    'idx_sentence': 'CREATE INDEX IF NOT EXISTS epi.idx_sentence '
        'ON sentences(book_id, para_id, line_id)',
    'idx_heading': 'CREATE INDEX IF NOT EXISTS epi.idx_heading '
        'ON headings(book_id, para_id)',
    'idx_link_src': 'CREATE INDEX IF NOT EXISTS epi.idx_link_src '
        'ON book_links(src_book, src_para)',
    'idx_link_dst': 'CREATE INDEX IF NOT EXISTS epi.idx_link_dst '
        'ON book_links(dst_book, dst_para)',
  };

  static Future<void> _ensureSentenceIndexes(Database db) async {
    try {
      final have = (await db.rawQuery(
              "SELECT name FROM epi.sqlite_master WHERE type='index'"))
          .map((r) => r['name'] as String)
          .toSet();
      final missing = _sentenceIndexes.entries
          .where((e) => !have.contains(e.key))
          .toList();
      if (missing.isEmpty) return;

      myLogger.i('building ${missing.length} sentence indexes');
      final started = DateTime.now();
      for (final entry in missing) {
        await db.execute(entry.value);
      }
      myLogger.i('sentence indexes built in '
          '${DateTime.now().difference(started).inMilliseconds} ms');
    } catch (e) {
      // Reading still works without them, only slowly, and a database opened
      // read-only cannot be given them at all.
      myLogger.e('could not build the sentence indexes: $e');
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
      // A download or copy cut off part way, by the app being closed or the
      // phone dying. Only ever unfinished: an install renames its file to
      // the real name as its last step.
      for (final leftover in Directory(dbPath)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith(LanguageInstaller.unfinished))) {
        try {
          leftover.deleteSync();
          myLogger.i('removed unfinished ${basename(leftover.path)}');
        } catch (_) {}
      }
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
        } catch (e) {
          myLogger.e('could not attach language $code: $e');
          continue;
        }
        final complete = await languageComplete(db, code);
        if (complete == true) {
          codes.add(code);
          continue;
        }
        try {
          await db.execute('DETACH DATABASE lang_$code');
        } catch (_) {}
        if (complete == false) {
          // There, but with nothing in it, or an install that never
          // finished. Reading it would show no translation and search none,
          // as if installed. Removed, it is offered for download again.
          try {
            File(join(dbPath, name)).deleteSync();
            myLogger.e('language $code was incomplete and has been removed');
          } catch (e) {
            myLogger.e('language $code is incomplete and could not be '
                'removed: $e');
          }
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
    //
    // Not before the reader has made the translation choice, though. A reset
    // clears the preferences but keeps the language files, so every one of
    // them reads as just appeared; switching them all on showed languages
    // the reader had not asked for. The choice screen offers them instead,
    // and shows the ones chosen.
    final known = Prefs.knownLanguages;
    final fresh = codes.where((c) => !known.contains(c)).toList();
    if (fresh.isNotEmpty && Prefs.languageChoiceMade) {
      Prefs.knownLanguages = [...known, ...fresh];
      Prefs.activeLanguages = [
        ...Prefs.activeLanguages.where(codes.contains),
        ...fresh,
      ];
      myLogger.i('showing languages: ${Prefs.activeLanguages.join(", ")}');
    }
    myLogger.i('languages attached: ${codes.isEmpty ? "none" : codes.join(", ")}');
  }

  /// Whether an attached language file holds a whole translation.
  ///
  /// True when its sentences table has rows and, for a file installed with
  /// the record of it, the install got to its end. False when either is
  /// missing. Null when the file could not be asked at all, which says
  /// nothing about it, so nothing is done to it.
  static Future<bool?> languageComplete(Database db, String code) async {
    try {
      final rows = await db.rawQuery(
          'SELECT EXISTS(SELECT 1 FROM lang_$code.sentences) AS n');
      if ((rows.first['n'] as int? ?? 0) == 0) return false;
      final meta = await db.rawQuery(
          "SELECT count(*) AS n FROM lang_$code.sqlite_master "
          "WHERE type = 'table' AND name = 'meta'");
      // Files from before the record was kept have none; rows are all
      // they can show.
      if ((meta.first['n'] as int? ?? 0) == 0) return true;
      final done = await db.rawQuery(
          "SELECT value FROM lang_$code.meta WHERE key = 'complete'");
      return done.isNotEmpty;
    } catch (e) {
      myLogger.e('could not check language $code: $e');
      return null;
    }
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

  /// The whole after-open chain: build the index, retire the old data,
  /// reclaim the space. Held so it can be waited on before closing.
  static Future<bool>? _setupChain;

  /// Whether a table is present in the main database.
  static Future<bool> hasTable(Database db, String name) async {
    final rows = await db.rawQuery(
        "SELECT count(*) AS n FROM sqlite_master "
        "WHERE type='table' AND name = ?",
        [name]);
    return ((rows.first['n'] as int?) ?? 0) > 0;
  }

  /// Index work runs one job at a time, in the order asked for.
  ///
  /// Handing a second caller the build already in flight was not enough: that
  /// build had been started with the languages installed at the time, so a
  /// language installed while it ran was never indexed. Queued, the second
  /// call runs after the first and finds the language missing.
  ///
  /// Attaching and detaching a language go through the same queue, because a
  /// language file cannot be detached while a build is reading it.
  static Future<void> _indexQueue = Future.value();

  static Future<T> _serial<T>(Future<T> Function() task) {
    final next = _indexQueue.then((_) => task());
    _indexQueue = next.then((_) {}, onError: (_) {});
    return next;
  }

  /// What the index work is doing right now, for a screen that wants to show
  /// it. Null when nothing is running.
  static final ValueNotifier<String?> indexStatus = ValueNotifier(null);

  Future<int> buildSentenceFtsIfNeeded({
    void Function(String message)? onProgress,
  }) {
    final started = _serial(() => _buildSentenceFts(onProgress: (message) {
          indexStatus.value = message;
          onProgress?.call(message);
        }).whenComplete(() => indexStatus.value = null));
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
    // Follow the set of installed languages, so adding or removing one is
    // reflected in search rather than silently ignored.
    final indexed = await SentenceFtsBuilder.indexedLanguages(db);
    final wanted = [...installedLanguages]..sort();
    final built = await SentenceFtsBuilder.isBuilt(db);
    try {
      if (built) {
        sentenceSearchAvailable = true;
        if (!await SentenceFtsBuilder.translationIndexCurrent(db)) {
          // Built before marks were kept inside words. Only the translation
          // half is redone; the Pali index is left as it is.
          myLogger.i('rebuilding the translation index');
          await SentenceFtsBuilder.rebuildTranslations(db, wanted,
              onProgress: onProgress);
          return 0;
        }
        final removed = indexed.where((c) => !wanted.contains(c)).toList();
        final added = wanted.where((c) => !indexed.contains(c)).toList();
        // Only the language that changed; the Pali and the other languages
        // are untouched by it.
        for (final code in removed) {
          await SentenceFtsBuilder.removeLanguage(db, code);
        }
        for (final code in added) {
          await SentenceFtsBuilder.addLanguage(db, code,
              onProgress: onProgress);
        }
        if (removed.isNotEmpty || added.isNotEmpty) {
          myLogger.i('translation index now covers: ${wanted.join(", ")}');
        }
        return 0;
      }
      final count = await SentenceFtsBuilder.build(db,
          languages: installedLanguages, onProgress: onProgress);
      sentenceSearchAvailable = count > 0;
      myLogger.i('sentence search index built: $count units');
      return count;
    } catch (e) {
      if (built) {
        // The Pali index is whole; only a language is missing from it, and
        // the next start tries that language again.
        myLogger.e('indexing a translation failed: $e');
        rethrow;
      }
      // A part-written index reads as a whole one and would quietly search a
      // fraction of the canon. Take it away and leave the next start to
      // build it again.
      sentenceSearchAvailable = false;
      myLogger.e('search index build failed, discarding it: $e');
      await SentenceFtsBuilder.discard(db);
      rethrow;
    }
  }

  /// Puts the installed languages' words into the search suggestions, and
  /// takes out the words of any that have gone. Queued with the index work,
  /// so it never runs alongside an install doing the same.
  Future<void> updateTranslationWordLists({
    void Function(String message)? onProgress,
  }) =>
      _serial(() async {
        if (!sentenceDataAvailable) return;
        await LegacyDataRetirement.ensureTranslationWordLists(await database,
            onProgress: (message) {
          indexStatus.value = message;
          onProgress?.call(message);
        });
        indexStatus.value = null;
      });

  /// Takes a language out of search so it is indexed again from its file,
  /// for when the file has been replaced by a fresh download.
  Future<void> forgetLanguageIndex(String code) => _serial(() async {
        final db = await database;
        if (!await SentenceFtsBuilder.isBuilt(db)) return;
        await SentenceFtsBuilder.removeLanguage(db, code);
      });

  /// Attaches a newly installed language to the open database.
  ///
  /// Installing used to close the database and open it again to pick the
  /// file up. Everything else holding the old handle — the book list, an
  /// open reader — then failed against a closed database, which is the blank
  /// book list and the hang after an install. Attaching to the connection
  /// that is already open needs none of that.
  Future<void> attachLanguage(String code) => _serial(() async {
        if (installedLanguages.contains(code)) return;
        final db = await database;
        final path = join(Prefs.databaseDirPath, 'lang_$code.db');
        await db.execute('ATTACH DATABASE ? AS lang_$code', [path]);
        if (await languageComplete(db, code) != true) {
          await db.execute('DETACH DATABASE lang_$code');
          throw Exception('the $code translation is incomplete');
        }
        installedLanguages = [...installedLanguages, code]..sort();
        myLogger.i('language attached: $code');
      });

  /// Detaches a language so its file can be deleted.
  Future<void> detachLanguage(String code) => _serial(() async {
        if (!installedLanguages.contains(code)) return;
        final db = await database;
        installedLanguages =
            installedLanguages.where((c) => c != code).toList();
        await db.execute('DETACH DATABASE lang_$code');
        myLogger.i('language detached: $code');
      });

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
    // Wait for the work started when the database was opened rather than
    // closing it underneath. Both setup and installing a language close and
    // reopen, and either can land in the middle of an index build.
    for (final pending in [_ftsBuild, _setupChain, _indexQueue]) {
      if (pending == null) continue;
      try {
        await pending;
      } catch (_) {
        // Its own caller reports it; here it only has to have finished.
      }
    }
    _setupChain = null;
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
    if (await hasTable(dbInstance, 'pages')) {
      await dbInstance.execute(
        'CREATE INDEX IF NOT EXISTS page_index ON pages ( bookid );',
      );
    }
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

    // The page index is built from the page text. A database shipped without
    // it has nothing to index here, and the sentence index built afterwards
    // is what search uses.
    if (!await hasTable(dbInstance, 'pages')) {
      updateMessageCallback('Search index will be built from the sentences');
      return true;
    }
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
