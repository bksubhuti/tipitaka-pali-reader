import 'package:sqflite_common/sqlite_api.dart';

/// The reader's own data, carried from the old database into a newly shipped
/// one when the database version moves.
///
/// An update replaces `tipitaka_pali.db` with the copy in the app. It used to
/// carry the bookmarks across and nothing else, so every update emptied the
/// bookmark folders, the recent books, the search and dictionary history, and
/// put the dictionaries back in their default order. Worse, bookmarks kept
/// pointing at folders that were no longer there.
///
/// Rows keep their ids, so a bookmark stays in its folder. Only columns
/// present on both sides are copied, so a table that gained or lost a column
/// between versions still comes across.
class UserDataCarryOver {
  /// Copied whole. Folders before bookmarks, which refer to them.
  static const tables = [
    'folder',
    'bookmark',
    'recent',
    'search_history',
    'dictionary_history',
  ];

  final Map<String, List<Map<String, Object?>>> _rows;

  /// The reader's order and choice of dictionaries, by dictionary id. The
  /// dictionaries themselves ship with the app; only these two settings are
  /// the reader's.
  final List<Map<String, Object?>> _dictionaryChoices;

  UserDataCarryOver._(this._rows, this._dictionaryChoices);

  int get bookmarkCount => _rows['bookmark']?.length ?? 0;

  /// Reads everything worth keeping out of [old]. A table that is not there
  /// is skipped; this never fails an update over data that was never kept.
  static Future<UserDataCarryOver> read(DatabaseExecutor old) async {
    final rows = <String, List<Map<String, Object?>>>{};
    for (final table in tables) {
      if (!await _exists(old, table)) continue;
      try {
        rows[table] = await old.query(table);
      } catch (_) {}
    }
    var choices = <Map<String, Object?>>[];
    if (await _exists(old, 'dictionary_books')) {
      try {
        choices = await old.query('dictionary_books',
            columns: ['id', 'user_order', 'user_choice']);
      } catch (_) {}
    }
    return UserDataCarryOver._(rows, choices);
  }

  /// Writes it into [db], replacing any row with the same id.
  Future<void> writeTo(Database db) async {
    for (final table in tables) {
      final rows = _rows[table];
      if (rows == null || rows.isEmpty) continue;
      if (!await _exists(db, table)) continue;
      final columns = (await db.rawQuery('PRAGMA table_info($table)'))
          .map((c) => c['name'] as String)
          .toSet();
      final batch = db.batch();
      for (final row in rows) {
        batch.insert(
          table,
          {
            for (final entry in row.entries)
              if (columns.contains(entry.key)) entry.key: entry.value,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    }

    if (_dictionaryChoices.isNotEmpty &&
        await _exists(db, 'dictionary_books')) {
      final batch = db.batch();
      for (final choice in _dictionaryChoices) {
        batch.update(
          'dictionary_books',
          {
            'user_order': choice['user_order'],
            'user_choice': choice['user_choice'],
          },
          where: 'id = ?',
          whereArgs: [choice['id']],
        );
      }
      await batch.commit(noResult: true);
    }
  }

  static Future<bool> _exists(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
        "SELECT count(*) AS n FROM sqlite_master "
        "WHERE type='table' AND name = ?",
        [table]);
    return ((rows.first['n'] as int?) ?? 0) > 0;
  }
}
