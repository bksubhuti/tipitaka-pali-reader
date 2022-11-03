import 'package:flutter/material.dart';
import 'dart:io';

import 'package:internet_connection_checker/internet_connection_checker.dart';

import 'package:archive/archive_io.dart';

import '../../../business_logic/models/download_list_item.dart';
import 'download_notifier.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:dio/dio.dart';

class DownloadService {
  DownloadNotifier downloadNotifier;
  DownloadListItem downloadListItem;

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
      final db = await dbService.database;
      await doDeletes(db, sql);
      await doInserts(db, sql);
    }
    downloadNotifier.downloading = false;
  }

  Future<void> doDeletes(db, String sql) async {
    sql = sql.toLowerCase();
    List<String> lines = sql.split("\n");
    StringBuffer sb = StringBuffer("");

    for (String line in lines) {
      if (line.contains("delete")) {
        sb.writeln(line);
      }
    }

    String deleteSql = sb.toString();

    if (deleteSql.isNotEmpty) {
      await db.transaction((txn) async {
        int id1 = await txn.rawDelete(deleteSql);
        debugPrint('deleted: $id1');
      });
    }
  }

  Future<void> doInserts(db, String sql) async {
    sql = sql.toLowerCase();
    List<String> lines = sql.split("\n");
    StringBuffer sb = StringBuffer("");

    for (String line in lines) {
      if (line.contains("insert")) {
        sb.writeln(line);
      }
    }

    String insertSql = sb.toString();
    if (insertSql.isNotEmpty) {
      await db.transaction((txn) async {
        int id1 = await txn.rawInsert(insertSql);
        debugPrint('inserted1: $id1');
      });
    }
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
}
