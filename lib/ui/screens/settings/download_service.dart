import 'dart:collection';

import 'package:flutter/material.dart';
import 'dart:io';

import 'package:internet_connection_checker/internet_connection_checker.dart';

import 'package:archive/archive_io.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../../business_logic/models/download_list_item.dart';
import 'download_notifier.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:dio/dio.dart';

class DownloadService {
  DownloadNotifier downloadNotifier;
  DownloadListItem downloadListItem;
  int batchAmount = 500;

  String _dir = "";

  late final String _zipPath;
  late final String _localZipFileName;
  final dbService = DatabaseHelper();

  DownloadService(
      {required this.downloadNotifier, required this.downloadListItem}) {
    _zipPath = downloadListItem.url;

    _localZipFileName = downloadListItem.filename;
  }

  Future<String> get _localPath async {
    return Prefs.databaseDirPath;
  }

  Future<File> get _localFile async {
    final path = Prefs.databaseDirPath;
    return File('$path/$_localZipFileName');
  }

  Future<String> getSQL() async {
    await downloadZip();
    final file = await _localFile;

    // Read the file
    String s = await file.readAsString();
    return s;
  }

  Future<void> downloadZip() async {
    var zippedFile = await downloadFile(_zipPath, _localZipFileName);
    await unarchiveAndSave(zippedFile);
  }

  Future<void> installSqlZip() async {
    initDir();

    // check to see if there is a connection
    bool hasInternet = await InternetConnectionChecker().hasConnection;
    downloadNotifier.message = "Internet connection = $hasInternet";
    if (hasInternet) {
      downloadNotifier.downloading = true;
      downloadNotifier.message =
          "\nNow downlading file.. ${downloadListItem.size}\nPlease Wait.";
      // now read a file
      String sql = await getSQL();
      Database db = await dbService.database;
      final newBooks = await doDeletes(db, sql);
      await doInserts(db, sql);
      await doUpdates(db, sql);
      downloadNotifier.message = 'Building fts';
      await doFts(db, newBooks);
    }
    downloadNotifier.downloading = false;
  }

  Future<Set<String>> doDeletes(Database db, String sql) async {
    Set<String> newBooks = <String>{};
    RegExp reBookId = RegExp("'.+'");
    sql = sql.toLowerCase();
    List<String> lines = sql.split("\n");
    //StringBuffer sb = StringBuffer("");

    //String deleteSql = sb.toString();
    downloadNotifier.message = "\nNow Deleting Records";

    if (lines.isNotEmpty) {
      var batch = db.batch();
      for (String line in lines) {
        if (line.contains("delete")) {
          if (line.contains('delete from books')) {
            final match = reBookId.firstMatch(line)!;
            newBooks.add(match[0]!);
          }
          batch.rawDelete(line);
        }
      }
      await batch.commit();
    }
    return newBooks;
  }

  Future<void> doInserts(Database db, String sql) async {
    sql = sql.toLowerCase();
    List<String> lines = sql.split("\n");
    var batch = db.batch();

    int counter = 0;
    for (String line in lines) {
      if (line.contains("insert")) {
        batch.rawInsert(line);
        counter++;
        if (batchAmount % counter == 1) {
          await batch.commit(noResult: true);
          downloadNotifier.message =
              "inserted $counter of ${lines.length}: ${(counter / lines.length * 100).toStringAsFixed(0)}%";
          batch = db.batch();
        }
      }
    }
    await batch.commit(noResult: true);

    downloadNotifier.message = "Insert is complete";
  }

  Future<void> doUpdates(Database db, String sql) async {
    sql = sql.toLowerCase();
    List<String> lines = sql.split("\n");
    var batch = db.batch();

    int counter = 0;
    for (String line in lines) {
      if (line.contains("update")) {
        batch.rawUpdate(line);
        counter++;
        if (counter % batchAmount == 1) {
          await batch.commit(noResult: true);
          downloadNotifier.message =
              "updated $counter of ${lines.length}: ${(counter / lines.length * 100).toStringAsFixed(0)}%";
          batch = db.batch();
        }
      }
    }
    await batch.commit(noResult: true);

    downloadNotifier.message = "Update is complete";
  }

  Future<void> doFts(Database db, Set<String> newBooks) async {
    int maxWrites = 50;
    var batch = db.batch();
    int counter = 0;
    for (final bookId in newBooks) {
      final qureySql =
          'SELECT id, bookid, page, content, paranum FROM pages WHERE bookid = $bookId';
      final maps = await db.rawQuery(qureySql);
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
        counter++;
        if (counter % maxWrites == 1) {
          await batch.commit(noResult: true);
          String pcent = (counter / maps.length * 100).toStringAsFixed(0);
          downloadNotifier.message = "inserted $counter";
          batch = db.batch();
        }
      }
      // commit remainder inserts after the loop stops.
      await batch.commit(noResult: true);
    }
    downloadNotifier.message = "FTS is complete";
  }

  void showDownloadProgress(received, total) {
    if (total != -1) {
      String percent = (received / total * 100).toStringAsFixed(0);
      downloadNotifier.message = "Downloading: $percent %\n";
    }
  }

  Future<File> downloadFile(String url, String fileName) async {
    var req = await Dio().get(
      url,
      onReceiveProgress: showDownloadProgress,
      options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (status) {
            return status! < 500;
          }),
    );
    if (req.statusCode == 200) {
      var file = File('$_dir/$fileName');
      debugPrint("file.path ${file.path}");
      downloadNotifier.message += "\nfile.path =  ${file.path}\n";
      return file.writeAsBytes(req.data);
    } else {
      throw Exception('Failed to load zip file');
    }
  }

  initDir() async {
    _dir = Prefs.databaseDirPath;
  }

  Future<void> unarchiveAndSave(var zippedFile) async {
    var bytes = zippedFile.readAsBytesSync();
    var archive = ZipDecoder().decodeBytes(bytes);
    for (var file in archive) {
      var fileName = '$_dir/${file.name}';
      debugPrint("fileName $fileName");
      downloadNotifier.message += "\nExtracting filename = $fileName\n";
      if (file.isFile && !fileName.contains("__MACOSX")) {
        var outFile = File(fileName);
        outFile = await outFile.create(recursive: true);
        await outFile.writeAsBytes(file.content);
      }
    }
    downloadNotifier.message = "\nDownloaded ${archive.length} files";
  }

  String _cleanText(String text) {
    final regexHtmlTags = RegExp(r'<[^>]*>');
    return text.replaceAll(regexHtmlTags, '');
  }
}