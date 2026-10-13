import 'dart:convert';

import 'package:firedart/firedart.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:tipitaka_pali/business_logic/models/bookmark.dart';
import 'package:tipitaka_pali/business_logic/models/folder.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/repositories/bookmark_fire_repo.dart';
import 'package:tipitaka_pali/utils/simple_encryptor.dart';

/// What a cloud backup holds, read from its summary without the data.
class BookmarkBackupInfo {
  final DateTime created;
  final int folderCount;
  final int bookmarkCount;

  BookmarkBackupInfo(this.created, this.folderCount, this.bookmarkCount);
}

/// Why a backup could not be made or read. The dialog shows each in the
/// reader's language.
enum BookmarkBackupFailure { encrypt, read }

class BookmarkBackupException implements Exception {
  final BookmarkBackupFailure failure;

  BookmarkBackupException(this.failure);

  @override
  String toString() => switch (failure) {
        BookmarkBackupFailure.encrypt => 'The backup could not be encrypted.',
        BookmarkBackupFailure.read => 'The backup could not be read. '
            'Was it made before a password change?',
      };
}

/// One snapshot of every bookmark folder and bookmark, kept in the cloud at
/// `users/<email>/backups`.
///
/// The `folder` and `bookmark` rows go up whole, ids included, as one
/// encrypted JSON string. Restoring replaces both tables with those rows, so
/// every bookmark lands back in its folder and every folder under its parent
/// without any id mapping.
///
/// The string is split across documents to stay under Firestore's 1 MB limit.
/// The parts are written first and the `latest` summary last, so an
/// interrupted backup leaves the previous one readable.
///
/// The hidden root folder (id -1) holds the bookmarks that are in no folder.
/// It goes up and comes back with the rest, is not counted as a folder, and
/// is put back if a backup lacks it.
///
/// The key is the account password: after a password change, older backups
/// can no longer be read.
class BookmarkBackupRepository {
  static const _tables = ['folder', 'bookmark'];
  static const _partSize = 800000;
  static const _writesPerCommit = 100;
  static const _rootId = -1;

  final DatabaseHelper _databaseHelper;
  final SimpleEncryptor _crypto = SimpleEncryptor(Prefs.password);

  BookmarkBackupRepository(this._databaseHelper);

  CollectionReference get _backups => Firestore.instance
      .collection('users')
      .document(Prefs.email)
      .collection('backups');

  /// The summary of the cloud backup, or null when there is none.
  Future<BookmarkBackupInfo?> info() async {
    await BookmarkFireRepository().ensureSignedIn();
    final latest = _backups.document('latest');
    if (!await latest.exists) return null;
    final doc = await latest.get();
    return BookmarkBackupInfo(
      DateTime.parse(doc['created']),
      doc['folders'],
      doc['bookmarks'],
    );
  }

  /// The number of folders and bookmarks on this device.
  Future<(int, int)> localCounts() async {
    final db = await _databaseHelper.database;
    Future<int> count(String sql) async =>
        (await db.rawQuery(sql)).first['n'] as int;
    return (
      await count('SELECT COUNT(*) AS n FROM folder WHERE id != $_rootId'),
      await count('SELECT COUNT(*) AS n FROM bookmark'),
    );
  }

  /// Sends every folder and bookmark on this device to the cloud, replacing
  /// the backup that was there.
  Future<BookmarkBackupInfo> backUp() async {
    await BookmarkFireRepository().ensureSignedIn();
    final db = await _databaseHelper.database;
    final rows = {for (final table in _tables) table: await db.query(table)};
    final cipher = _crypto.encryptText(jsonEncode({'format': 1, ...rows}));
    if (cipher.isEmpty || cipher == '404') {
      throw BookmarkBackupException(BookmarkBackupFailure.encrypt);
    }

    final set = DateTime.now().millisecondsSinceEpoch.toString();
    final parts = <String>[
      for (var i = 0; i < cipher.length; i += _partSize)
        cipher.substring(i, (i + _partSize).clamp(0, cipher.length)),
    ];
    for (var i = 0; i < parts.length; i++) {
      await _backups.document('${set}_$i').set({'data': parts[i]});
    }

    final info = BookmarkBackupInfo(
        DateTime.now().toUtc(),
        rows['folder']!.where((f) => f['id'] != _rootId).length,
        rows['bookmark']!.length);
    await _backups.document('latest').set({
      'created': info.created.toIso8601String(),
      'folders': info.folderCount,
      'bookmarks': info.bookmarkCount,
      'set': set,
      'parts': parts.length,
    });

    // The parts of earlier backups.
    for (final doc in await _backups.get()) {
      if (doc.id != 'latest' && !doc.id.startsWith('${set}_')) {
        try {
          await doc.reference.delete();
        } catch (e) {
          debugPrint('Could not delete old backup part ${doc.id}: $e');
        }
      }
    }
    return info;
  }

  /// The folders and bookmarks in the cloud backup, without touching this
  /// device.
  Future<(List<Folder>, List<Bookmark>)> contents() async {
    final data = await _read();
    return (
      [
        for (final row in (data['folder'] as List? ?? []))
          if (row['id'] != _rootId) Folder.fromJson(row)
      ],
      [
        for (final row in (data['bookmark'] as List? ?? []))
          Bookmark.fromJson(row)
      ],
    );
  }

  /// Replaces every folder and bookmark on this device with the cloud backup.
  Future<void> restore() async {
    final data = await _read();

    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      // Bookmarks first, then their folders.
      for (final table in _tables.reversed) {
        await txn.delete(table);
      }
      for (final table in _tables) {
        final columns = (await txn.rawQuery('PRAGMA table_info($table)'))
            .map((c) => c['name'] as String)
            .toSet();
        final rows = (data[table] as List? ?? []).cast<Map<String, dynamic>>();
        for (var i = 0; i < rows.length; i += _writesPerCommit) {
          final batch = txn.batch();
          for (final row in rows.skip(i).take(_writesPerCommit)) {
            batch.insert(table, {
              for (final entry in row.entries)
                if (columns.contains(entry.key)) entry.key: entry.value,
            });
          }
          await batch.commit(noResult: true);
          await Future.delayed(Duration.zero);
        }
      }
      await txn.insert('folder', {'id': _rootId, 'name': 'root'},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    });
  }

  /// Fetches and decrypts the backup named by `latest`.
  Future<Map<String, dynamic>> _read() async {
    await BookmarkFireRepository().ensureSignedIn();
    final latest = await _backups.document('latest').get();
    final String set = latest['set'];
    final int partCount = latest['parts'];
    final cipher = StringBuffer();
    for (var i = 0; i < partCount; i++) {
      cipher.write((await _backups.document('${set}_$i').get())['data']);
    }
    try {
      return jsonDecode(_crypto.decryptText(cipher.toString()));
    } catch (_) {
      throw BookmarkBackupException(BookmarkBackupFailure.read);
    }
  }
}
