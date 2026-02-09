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
    initialSetupNotifier.setupIsFinished = false;
    debugPrint('isUpdateMode : $isUpdateMode');

    late String databasesDirPath;

    final docDirPath = await getApplicationSupportDirectory();
    databasesDirPath = docDirPath.path;
    // final databasesDirPath = await getApplicationDocumentsDirectory();
    final dbFilePath = join(databasesDirPath, DatabaseInfo.fileName);

    final recents = <Map<String, Object?>>[];
    //final bookmarks = <Map<String, Object?>>[];
    List<Bookmark> bookmarks = [];
    final dictionaryHistories = <Map<String, Object?>>[];
    final searchHistories = <Map<String, Object?>>[];
    final dictionaries = <Map<String, Object?>>[];

    // because a new db is copied.. the extension dpdgrammar is lost
    setDpdGrammarFlag(true);

    if (isUpdateMode) {
      // backuping user data to memory
      // There is a suscpicion that database migration is causing a bug.
      // so we only backup the bookmarks.
      //recents.addAll(await databaseHelper.backup(tableName: 'recent'));
      //bookmarks.addAll(await databaseHelper.backup(tableName: 'bookmark'));
      final DatabaseHelper databaseHelper = DatabaseHelper();
      final bmDbRepo = BookmarkDatabaseRepository(databaseHelper);
      bookmarks = await bmDbRepo.getAllBookmark();

      // backup history to memory
      /*try {
        dictionaryHistories.addAll(
            await databaseHelper.backup(tableName: 'dictionary_history'));
        searchHistories
            .addAll(await databaseHelper.backup(tableName: 'search_history'));
      } on DatabaseException catch (e) {
        // Todo: Handle the exception
        debugPrint('SQLite exception: $e');
      } catch (e) {
        debugPrint('Exception: $e');
      }
*/
      //dictionaries
      //  .addAll(await databaseHelper.backup(tableName: 'dictionary_books'));

      //debugPrint('dictionary books: ${dictionaries.length}');
      await databaseHelper.close();
      // deleting old database file
    }

    await deleteDatabase(dbFilePath);

    // make sure the folder exists
    if (!await Directory(databasesDirPath).exists()) {
      debugPrint('creating db folder path: $databasesDirPath');
      try {
        await Directory(databasesDirPath).create(recursive: true);
      } catch (e) {
        debugPrint('$e');
      }
    }

    // copying new database from assets
    await _copyFromAssets(dbFilePath);

    final DatabaseHelper databaseHelper = DatabaseHelper();

    // restoring user data
    /*
    if (recents.isNotEmpty) {
      await databaseHelper.restore(tableName: 'recent', values: recents);
    }
    */
    //recents.addAll(await databaseHelper.backup(tableName: 'recent'));
    //bookmarks.addAll(await databaseHelper.backup(tableName: 'bookmark'));
    final bmDbRepo = BookmarkDatabaseRepository(databaseHelper);

    // right now the only thing we restore is bookmarks.
    // the bookmark class handles default values.
    if (bookmarks.isNotEmpty) {
      for (Bookmark bm in bookmarks) {
        bmDbRepo.insert(bm);
      }
    }

// restore history from memory
/*
    try {
      await databaseHelper.restore(
          tableName: 'dictionary_history', values: dictionaryHistories);
      await databaseHelper.restore(
          tableName: 'search_history', values: searchHistories);
    } on DatabaseException catch (e) {
      // Todo: Handle the exception
      debugPrint('SQLite exception: $e');
    } catch (e) {
      debugPrint('Exception: $e');
    }
    // dictionary_books table is semi-user data
    // need to delete before restoring
    if (dictionaries.isNotEmpty) {
      await databaseHelper.deleteDictionaryData();
      debugPrint('dictionary books: ${dictionaries.length}');
      await databaseHelper.restore(
          tableName: 'dictionary_books', values: dictionaries);
    }
    */

    // save record to shared Preference
    Prefs.isDatabaseSaved = true;
    Prefs.databaseVersion = DatabaseInfo.version;

    initialSetupNotifier.setupIsFinished = true;
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
