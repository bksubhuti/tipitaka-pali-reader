import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tipitaka_pali/data/constants.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/prefs.dart';

class InitialSetupViewModel extends ChangeNotifier {
  final BuildContext _context;
  String _status = '';
  void updateMessageCallback(String msg) {
    _status = msg;
    notifyListeners();
  }

  InitialSetupViewModel(this._context);
  String get status => _status;

  Future<void> setUp(bool isUpdateMode) async {
    debugPrint('isUpdateMode : $isUpdateMode');

    late String databasesDirPath;

    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      databasesDirPath = await getDatabasesPath();
    }
    if (Platform.isLinux || Platform.isWindows) {
      final docDirPath = await getApplicationSupportDirectory();
      databasesDirPath = docDirPath.path;
    }
    // final databasesDirPath = await getApplicationDocumentsDirectory();
    final dbFilePath = join(databasesDirPath, DatabaseInfo.fileName);

    final recents = <Map<String, Object?>>[];
    final bookmarks = <Map<String, Object?>>[];
    final dictionaries = <Map<String, Object?>>[];

    if (isUpdateMode) {
      // backuping user data to memory
      final DatabaseHelper databaseHelper = DatabaseHelper();
      recents.addAll(await databaseHelper.backup(tableName: 'recent'));
      bookmarks.addAll(await databaseHelper.backup(tableName: 'bookmark'));
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
    if (recents.isNotEmpty) {
      await databaseHelper.restore(tableName: 'recent', values: recents);
    }

    if (bookmarks.isNotEmpty) {
      await databaseHelper.restore(tableName: 'bookmark', values: bookmarks);
    }

    // dictionary_books table is semi-user data
    // need to delete before restoring
    if (dictionaries.isNotEmpty) {
      await databaseHelper.deleteDictionaryData();
      debugPrint('dictionary books: ${dictionaries.length}');
      await databaseHelper.restore(
          tableName: 'dictionary_books', values: dictionaries);
    }

    // save record to shared Preference
    Prefs.isDatabaseSaved = true;
    Prefs.databaseVersion = DatabaseInfo.version;

    _openHomePage();
  }

  Future<void> _copyFromAssets(String dbFilePath) async {
    final dbFile = File(dbFilePath);
    final timeBeforeCopy = DateTime.now();
    final int count = AssetsFile.partsOfDatabase.length;
    int partNo = 0;
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
      _status = "Finished copying $percent% of database.";

      notifyListeners();
    }

    final timeAfterCopied = DateTime.now();
    debugPrint(
        'database copying time: ${timeAfterCopied.difference(timeBeforeCopy)}');

    // final isDbExist = await databaseExists(dbFilePath);
    // debugPrint('is db exist: $isDbExist');

    final timeBeforeIndexing = DateTime.now();

    // creating index tables

    final DatabaseHelper databaseHelper = DatabaseHelper();

    final indexResult = await databaseHelper.buildIndex();
    if (indexResult == false) {
      // handle error
    }

    // creating fts table
    final ftsResult = await DatabaseHelper().buildFts(updateMessageCallback);
    if (ftsResult == false) {
      // handle error
    }

    final timeAfterIndexing = DateTime.now();
    //_indexStatus =help
    notifyListeners();

    debugPrint(
        'indexing time: ${timeAfterIndexing.difference(timeBeforeIndexing)}');
  }

  void _openHomePage() {
    Navigator.of(_context).popAndPushNamed('/home');
  }
}
