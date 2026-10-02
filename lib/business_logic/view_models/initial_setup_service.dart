import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common/sqflite.dart';
import 'package:tipitaka_pali/data/constants.dart';
import 'package:tipitaka_pali/providers/initial_setup_notifier.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/database/sentence_data_installer.dart';
import 'package:tipitaka_pali/services/database/user_data_carry_over.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:tipitaka_pali/utils/platform_info.dart';

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

    // Setup opens and closes the database several times. The work that
    // normally starts when it opens reopens it whenever it needs it, so
    // leaving it running here meant it was still going when setup closed the
    // handle under it. It is run at the end instead, in order.
    DatabaseHelper.suspendBackgroundSetup = true;

    if (!isUpdateMode) {
      if (!PlatformInfo.isDesktop) {
        Prefs.hideScrollbar = true;
      }
    }

    // 1. Define the NEW Path (The "FFI" Goal)
    // We want the DB to live here permanently from now on.
    final appSupportDir = await getApplicationSupportDirectory();
    final newDbDir = appSupportDir.path;
    final newDbPath = join(newDbDir, DatabaseInfo.fileName);

    // The reader's own data, held while the database is replaced.
    UserDataCarryOver? userData;

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

          // Bookmarks with their folders, recents, history and the
          // dictionary order: everything the reader made, not only bookmarks.
          userData = await UserDataCarryOver.read(oldDb);

          debugPrint('--> Backed up ${userData.bookmarkCount} bookmarks '
              'and the rest of the reader\'s data.');
          await oldDb.close();
        } catch (e) {
          debugPrint('--> ERROR during backup: $e');
          // If backup fails, we proceed but log it.
          // We DO NOT delete the old file, so user data is still safe on disk.
        }
      }
    }

    // 3. PREPARE DESTINATION
    // We must close any active connections and delete the file at the NEW location.
    await DatabaseHelper().close();
    await deleteDatabase(newDbPath);

    // Ensure folder exists
    if (!await Directory(newDbDir).exists()) {
      await Directory(newDbDir).create(recursive: true);
    }

    // 4. COPY ASSETS
    await _copyFromAssets(newDbPath);

    // 4b. FORCE RE-INIT: Discard any stale DB handle that may have been
    // opened during the copy (e.g. by the Sangaha check running in parallel).
    await DatabaseHelper().close();

    // 5. UPDATE PREFS
    // Now that the file is in the new place, update Prefs immediately.
    // This ensures DatabaseHelper will find it there.
    Prefs.databaseDirPath = newDbDir;
    Prefs.isDatabaseSaved = true;
    Prefs.databaseVersion = DatabaseInfo.version;

    // 5b. CLEAN UP OBSOLETE LEGACY EXTENSIONS
    _cleanupLegacyFiles(newDbDir);

    // 6. RESTORE DATA
    if (userData != null) {
      debugPrint('--> Restoring the reader\'s data to new DB...');
      try {
        // Now it is safe to use the Singleton, because Prefs are updated!
        await userData.writeTo(await DatabaseHelper().database);
        debugPrint('--> Restore complete.');
      } catch (e) {
        debugPrint('--> ERROR during restore: $e');
      }
    }

    // 7. FINISH
    //
    // Now the database is settled: retire the page data the sentences have
    // taken over, and give back the space. The index itself was built during
    // the copy, so this usually has only the tidying left to do.
    try {
      await DatabaseHelper.runBackgroundSetupNow();
    } catch (e) {
      // Nothing here should stop the app opening; the next start retries.
      debugPrint('--> background setup after install failed: $e');
    }

    _intialSetupNotifier.setupIsFinished = true;
  }

  void _cleanupLegacyFiles(String dbDir) {
    const legacyNames = [
      'full_en.zip',
      'full_vn.zip',
      'en_full.zip',
      'vn_full.zip',
      'full_english.sql',
      'full_vietnamese.sql',
    ];
    // The ePitaka "full" extensions: the downloaded zip and the database
    // unpacked from it, a whole second copy of the canon with one
    // translation in its pages. Translations are language files now and
    // nothing opens these, so they are only space — over 500 MB for English.
    final retired = <String>[];
    try {
      for (final entry in Directory(dbDir).listSync().whereType<File>()) {
        final name = basename(entry.path);
        final fullZip = name.startsWith('epitaka_') &&
            name.contains('full') &&
            name.endsWith('.zip');
        final fullDb = name.startsWith('epitaka_') &&
            name.endsWith('_full.db');
        if (fullZip || fullDb) retired.add(name);
      }
    } catch (_) {}

    for (final name in [...legacyNames, ...retired]) {
      final file = File(join(dbDir, name));
      if (file.existsSync()) {
        try {
          file.deleteSync();
          debugPrint('Deleted obsolete legacy file: $name');
        } catch (e) {
          debugPrint('Could not delete legacy file $name: $e');
        }
      }
    }
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
    // The sentence data ships alongside the Pali pages. Written next to the
    // file just copied, not to Prefs.databaseDirPath, which still points at
    // the old location until step 5.
    //
    // Only put in place if it is not there. Replacing it is done before the
    // database is opened, not here: by now the reader has a connection with
    // these files attached to it, and they cannot be deleted under it.
    await SentenceDataInstaller.install(dirname(dbFilePath),
        onProgress: (msg) => _intialSetupNotifier.status = msg);

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

    // The sentence-based index, when ePitaka's data is installed. Built here
    // rather than shipped, so it always matches the data actually present.
    await DatabaseHelper().buildSentenceFtsIfNeeded(
      onProgress: (msg) => updateMessageCallback(msg),
    );

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
