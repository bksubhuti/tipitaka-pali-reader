import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common/sqflite.dart';
import 'package:tipitaka_pali/business_logic/models/bookmark.dart';
import 'package:tipitaka_pali/data/constants.dart';
import 'package:tipitaka_pali/providers/initial_setup_notifier.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:tipitaka_pali/services/repositories/bookmark_repo.dart';

//singleton model so setup will only get called one time in constructor
class InitialSetupService {
  InitialSetupService(
    this._context,
    this._intialSetupNotifier,
    bool isUpdateMode,
  );
  final BuildContext _context;
  final InitialSetupNotifier _intialSetupNotifier;
  InitialSetupNotifier get initialSetupNotifier => _intialSetupNotifier;

  List<File> extensions = [];
  String exList = "";

  void updateMessageCallback(String msg) {
    _intialSetupNotifier.status = msg;
  }

  Future<void> setUp(bool isUpdateMode) async {
    _intialSetupNotifier.setupIsFinished = false;
    debugPrint('--> Setup Starting. Update Mode: $isUpdateMode');

    // 1. Define the NEW Path (The "FFI" Goal)
    // We want the DB to live here permanently from now on.
    final appSupportDir = await getApplicationSupportDirectory();
    final newDbDir = appSupportDir.path;
    final newDbPath = join(newDbDir, DatabaseInfo.fileName);

    // Temp storage for data migration
    List<Bookmark> bookmarksToRestore = [];

    // 2. BACKUP PHASE (Only runs if updating)
    if (isUpdateMode) {
      debugPrint('--> Starting Backup Phase...');

      // A. Find the OLD path
      String oldDbPath = '';
      if (Prefs.databaseDirPath.isNotEmpty) {
        // Use the path saved in previous version's prefs
        oldDbPath = join(Prefs.databaseDirPath, DatabaseInfo.fileName);
      } else {
        // Fallback to standard mobile default (safe for old upgrades)
        final sysDbDir = await getDatabasesPath();
        oldDbPath = join(sysDbDir, DatabaseInfo.fileName);
      }

      final oldFile = File(oldDbPath);

      // B. Extract Data
      if (await oldFile.exists()) {
        try {
          // We use standard openDatabase here to read the old file safely
          // Note: On mobile, this uses standard platform channels.
          // On Desktop, we might need to ensure FFI is init, but usually safe.
          var oldDb = await openDatabase(oldDbPath);

          // Fetch Bookmarks
          final maps = await oldDb.query('bookmark');
          bookmarksToRestore = maps.map((x) => Bookmark.fromJson(x)).toList();

          debugPrint('--> Backed up ${bookmarksToRestore.length} bookmarks.');
          await oldDb.close();
        } catch (e) {
          debugPrint('--> ERROR during backup: $e');
          // If backup fails, we proceed but log it.
          // We DO NOT delete the old file, so user data is still safe on disk.
        }
      }
    }

    // 3. PREPARE DESTINATION
    // We must delete the file at the NEW location to ensure we copy a clean asset.
    // (This does not touch the Old Source file)
    await deleteDatabase(newDbPath);

    // Ensure folder exists
    if (!await Directory(newDbDir).exists()) {
      await Directory(newDbDir).create(recursive: true);
    }

    // 4. COPY ASSETS
    await _copyFromAssets(newDbPath);

    // 5. UPDATE PREFS
    // Now that the file is in the new place, update Prefs immediately.
    // This ensures DatabaseHelper will find it there.
    Prefs.databaseDirPath = newDbDir;
    Prefs.isDatabaseSaved = true;
    Prefs.databaseVersion = DatabaseInfo.version;

    // 6. RESTORE DATA
    if (bookmarksToRestore.isNotEmpty) {
      debugPrint('--> Restoring bookmarks to new DB...');

      // Now it is safe to use the Singleton, because Prefs are updated!
      final dbHelper = DatabaseHelper();
      final bmRepo = BookmarkDatabaseRepository(dbHelper);

      for (final bm in bookmarksToRestore) {
        await bmRepo.insert(bm);
      }
      debugPrint('--> Restore complete.');
    }

    // 7. FINISH
    _intialSetupNotifier.setupIsFinished = true;
  }

  Future<void> _copyFromAssets(String dbFilePath) async {
    final dbFile = File(dbFilePath);
    final timeBeforeCopy = DateTime.now();
    final int count = AssetsFile.partsOfDatabase.length;
    int partNo = 0;
    _intialSetupNotifier.status =
        AppLocalizations.of(_context)!.aboutToCopy + (count * 50).toString();
    await Future.delayed(const Duration(milliseconds: 3000));
    for (String part in AssetsFile.partsOfDatabase) {
      // reading from assets
      // using join method on assets path does not work for windows
      final bytes = await rootBundle.load(
          '${AssetsFile.baseAssetsFolderPath}/${AssetsFile.databaseFolderPath}/$part');
      // appending to output dbfile
      await dbFile.writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          mode: FileMode.append);
      int percent = ((++partNo / count) * 100).round();
      _intialSetupNotifier.status =
          "${AppLocalizations.of(_context)!.finishedCopying} $percent% \\ ~${count * 50} MB";
      await Future.delayed(const Duration(milliseconds: 300));
    }
    _intialSetupNotifier.stepsCompleted = 0;

    final timeAfterCopied = DateTime.now();
    debugPrint(
        'database copying time: ${timeAfterCopied.difference(timeBeforeCopy)}');

    // final isDbExist = await databaseExists(dbFilePath);
    // debugPrint('is db exist: $isDbExist');

    final timeBeforeIndexing = DateTime.now();

    // creating index tables
    _intialSetupNotifier.status =
        AppLocalizations.of(_context)!.buildingWordList;
    final DatabaseHelper databaseHelper = DatabaseHelper();

    // This is commented out.. because we ship with the wordllist now.
    //await databaseHelper.buildWordList(updateMessageCallback);
    _intialSetupNotifier.status =
        AppLocalizations.of(_context)!.finishedBuildingWordList;
    _intialSetupNotifier.stepsCompleted = 1;

    _intialSetupNotifier.status = "building indexes";
    final indexResult = await databaseHelper.buildBothIndexes();
    if (indexResult == false) {
      // handle error
    }
    _intialSetupNotifier.status =
        AppLocalizations.of(_context)!.finishedBuildingIndexes;
    _intialSetupNotifier.stepsCompleted = 2;
    // creating fts table
    final ftsResult = await DatabaseHelper().buildFts(updateMessageCallback);
    if (ftsResult == false) {
      // handle error
    }

    final timeAfterIndexing = DateTime.now();
    //_indexStatus =help

    debugPrint(
        'indexing time: ${timeAfterIndexing.difference(timeBeforeIndexing)}');
  }

  setDpdGrammarFlag(bool isOn) async {
    // if this function is called in setup.. that means the db does not have the
    // table.  It is unsure if this type of (commented out) query is supported in linux sqlflite
    // however, it is sure to not be included on this setup routine and it is sure to be turned
    // on during the install of extension.
    Prefs.isDpdGrammarOn = isOn;
  }
}
