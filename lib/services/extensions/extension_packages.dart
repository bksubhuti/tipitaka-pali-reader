import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'package:tipitaka_pali/app.dart';
import 'package:tipitaka_pali/data/constants.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/prefs.dart';

/// Extensions delivered as databases that say what to do with themselves.
///
/// An extension used to be a file of SQL statements, run line by line in
/// batches. A failure part way left half the rows written, and nothing
/// recorded that it had been installed, so an update that replaced the
/// databases took it away again without anyone knowing.
///
/// A package is a SQLite file with three kinds of table:
///
///   * `meta (key, value)`: `id`, `version`, `title`, `description`, and
///     `format`, the version of this layout it is written for;
///   * `commands (seq, phase, op, target, arg)`: the steps, in `seq` order,
///     for `phase` `install` or `remove`;
///   * any data tables the steps copy from.
///
/// The steps are:
///
///   * `sql`: run [arg] as it is. The package is attached as `pkg`, the
///     sentence extension as `ext`, so a step can reach any of them. This is
///     what lets a package change anything without new code in the app;
///   * `copy`: put every row of the package's table [arg] into [target]
///     (`main.books`, `ext.page_break`), replacing rows with the same key,
///     by the columns the two tables share;
///   * `reindex`: [arg] is a comma list of ePitaka books whose search index
///     must be brought up to date afterwards. That is code, not SQL, so it
///     runs once the rest is done.
///
/// Every `sql` and `copy` step of a phase runs in one transaction: a package
/// goes in whole or not at all.
///
/// Installed packages are kept, as `<id>.db` in [folderName] beside the
/// databases, and applied again whenever the databases they changed have
/// been replaced. `applied_package` in the main database records what was
/// applied, and against which sentence extension: an update that replaces
/// the main database takes the record with it, and one that replaces the
/// extension changes its stamp, and either way the next start applies the
/// package again.
class ExtensionPackages {
  ExtensionPackages._();

  /// The layout this app understands. A package written for a later one is
  /// refused rather than half understood.
  static const supportedFormat = 1;

  static const folderName = 'packages';

  static const _ops = {'sql', 'copy', 'reindex'};
  static final _name = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  static Directory folder(String dbDir) => Directory(join(dbDir, folderName));

  /// Runs [phase] of the package at [file] against [db], and returns the
  /// ePitaka books whose search index needs bringing up to date.
  ///
  /// [stamp] identifies the sentence extension the rows are going into, and
  /// is recorded with the package; see [currentStamp].
  static Future<List<String>> run(
    Database db,
    File file, {
    String phase = 'install',
    String stamp = '',
  }) async {
    final info = await read(file);
    await _detachQuietly(db);
    await db.execute('ATTACH DATABASE ? AS pkg', [file.path]);
    try {
      final commands = await db.rawQuery(
          'SELECT seq, op, target, arg FROM pkg.commands '
          'WHERE phase = ? ORDER BY seq',
          [phase]);
      // Checked before anything is written, so a package with a step this
      // app cannot do changes nothing.
      for (final c in commands) {
        final op = c['op'] as String? ?? '';
        if (!_ops.contains(op)) {
          throw PackageException('step ${c['seq']}: unknown step "$op"');
        }
        if (op == 'copy') {
          _split(c['target'] as String?, c['seq']);
          if (!_name.hasMatch(c['arg'] as String? ?? '')) {
            throw PackageException('step ${c['seq']}: no table to copy from');
          }
        }
      }

      final books = <String>[];
      await db.transaction((txn) async {
        await txn.execute('CREATE TABLE IF NOT EXISTS main.applied_package ('
            'id TEXT PRIMARY KEY, version INTEGER, stamp TEXT)');
        for (final c in commands) {
          final arg = c['arg'] as String? ?? '';
          switch (c['op']) {
            case 'sql':
              await txn.execute(arg);
            case 'copy':
              final (schema, table) = _split(c['target'] as String?, c['seq']);
              final into = (await txn.rawQuery('PRAGMA $schema.table_info($table)'))
                  .map((r) => r['name'] as String)
                  .toSet();
              if (into.isEmpty) {
                throw PackageException(
                    'step ${c['seq']}: there is no table $schema.$table');
              }
              final from = (await txn.rawQuery('PRAGMA pkg.table_info($arg)'))
                  .map((r) => r['name'] as String);
              final columns = from.where(into.contains).map((c) => '"$c"');
              if (columns.isEmpty) {
                throw PackageException('step ${c['seq']}: '
                    'pkg.$arg has no columns in common with $schema.$table');
              }
              final list = columns.join(', ');
              await txn.execute('INSERT OR REPLACE INTO $schema."$table" '
                  '($list) SELECT $list FROM pkg."$arg"');
            case 'reindex':
              books.addAll(arg
                  .split(',')
                  .map((b) => b.trim())
                  .where((b) => b.isNotEmpty));
          }
        }
        if (phase == 'install') {
          await txn.rawInsert(
              'INSERT OR REPLACE INTO main.applied_package VALUES (?, ?, ?)',
              [info.id, info.version, stamp]);
        } else {
          await txn.delete('applied_package',
              where: 'id = ?', whereArgs: [info.id]);
        }
      });
      return books;
    } finally {
      await _detachQuietly(db);
    }
  }

  /// What a package says about itself. Opened read-only and closed again.
  static Future<PackageInfo> read(File file) async {
    if (!file.existsSync()) throw PackageException('${file.path} is missing');
    final db = await openDatabase(file.path, readOnly: true,
        singleInstance: false);
    try {
      final rows = await db.rawQuery('SELECT key, value FROM meta');
      final meta = {
        for (final r in rows) r['key'] as String: r['value']?.toString() ?? ''
      };
      final id = meta['id'] ?? '';
      if (!_name.hasMatch(id)) {
        throw PackageException('the package has no usable id');
      }
      final format = int.tryParse(meta['format'] ?? '') ?? 0;
      if (format < 1 || format > supportedFormat) {
        throw PackageException('"$id" is written for a newer version of the '
            'app (format $format); please update the app');
      }
      await db.rawQuery('SELECT count(*) FROM commands');
      return PackageInfo(
        id: id,
        version: int.tryParse(meta['version'] ?? '') ?? 0,
        title: meta['title'] ?? id,
        description: meta['description'] ?? '',
        file: file,
      );
    } on DatabaseException catch (e) {
      throw PackageException('not an extension package: $e');
    } finally {
      await db.close();
    }
  }

  /// `main.books` to ('main', 'books'); only the main database and the
  /// sentence extension can be written to.
  static (String, String) _split(String? target, Object? seq) {
    final parts = (target ?? '').split('.');
    if (parts.length != 2 ||
        !const {'main', 'ext'}.contains(parts[0]) ||
        !_name.hasMatch(parts[1])) {
      throw PackageException('step $seq: cannot copy into "$target"');
    }
    return (parts[0], parts[1]);
  }

  static Future<void> _detachQuietly(Database db) async {
    try {
      await db.execute('DETACH DATABASE pkg');
    } catch (_) {
      // Not attached.
    }
  }

  // ---------------------------------------------------------------------
  // In the app

  static String get _dbDir => Prefs.databaseDirPath;

  /// The sentence extension's release, as recorded beside it when it was
  /// put in place. Changes when an update replaces the file.
  static String currentStamp([String? dbDir]) {
    final stamp = File(join(dbDir ?? _dbDir, '${AssetsFile.extensionFileName}.version'));
    try {
      return stamp.existsSync() ? stamp.readAsStringSync().trim() : '';
    } catch (_) {
      return '';
    }
  }

  /// The packages kept on this device.
  static Future<List<PackageInfo>> installed() async {
    final dir = folder(_dbDir);
    if (!dir.existsSync()) return const [];
    final out = <PackageInfo>[];
    for (final f in dir.listSync().whereType<File>()) {
      if (extension(f.path) != '.db') continue;
      try {
        out.add(await read(f));
      } catch (e) {
        myLogger.e('unreadable package ${f.path}: $e');
      }
    }
    return out;
  }

  /// Installs the package in [source], a `.db` or a `.zip` holding one, and
  /// keeps it so it can be applied again after an update.
  static Future<PackageInfo> install(File source,
      {void Function(String message)? onProgress}) async {
    final dir = folder(_dbDir)..createSync(recursive: true);
    final incoming = File(join(dir.path, 'incoming.part'));
    if (incoming.existsSync()) incoming.deleteSync();

    if (extension(source.path).toLowerCase() == '.zip') {
      onProgress?.call('Unpacking…');
      final archive = ZipDecoder().decodeBytes(await source.readAsBytes());
      final entry = archive.files.firstWhere(
          (f) => f.isFile && f.name.toLowerCase().endsWith('.db'),
          orElse: () => throw PackageException('no .db file in the zip'));
      await incoming.writeAsBytes(entry.content as List<int>, flush: true);
    } else {
      await source.copy(incoming.path);
    }

    PackageInfo info;
    try {
      info = await read(incoming);
    } catch (_) {
      incoming.deleteSync();
      rethrow;
    }

    final kept = File(join(dir.path, '${info.id}.db'));
    final db = await DatabaseHelper().database;
    await DatabaseHelper.runExclusive(() async {
      // The copy in place may be attached by a run still finishing.
      await _detachQuietly(db);
      if (kept.existsSync()) kept.deleteSync();
      await incoming.rename(kept.path);
    });
    info = PackageInfo(
        id: info.id,
        version: info.version,
        title: info.title,
        description: info.description,
        file: kept);

    await apply(info, onProgress: onProgress);
    return info;
  }

  /// Applies a kept package and indexes its books, and records that the
  /// reader has taken it, so it is applied again after an update.
  static Future<void> apply(PackageInfo info,
      {void Function(String message)? onProgress}) async {
    final db = await DatabaseHelper().database;
    onProgress?.call('Installing ${info.title}…');
    final books = await DatabaseHelper.runExclusive(
        () => run(db, info.file, stamp: currentStamp()));
    Prefs.acceptedPackages = [...Prefs.acceptedPackages, info.id];
    Prefs.declinedPackages =
        Prefs.declinedPackages.where((id) => id != info.id).toList();
    if (books.isNotEmpty) {
      onProgress?.call('Updating the search index…');
      await DatabaseHelper().reindexBooks(books);
    }
    onProgress?.call('${info.title} installed');
  }

  /// Takes out an installed package's changes and deletes it.
  static Future<void> remove(String id,
      {void Function(String message)? onProgress}) async {
    final kept = File(join(folder(_dbDir).path, '$id.db'));
    if (!kept.existsSync()) return;
    final db = await DatabaseHelper().database;
    final books =
        await DatabaseHelper.runExclusive(() => run(db, kept, phase: 'remove'));
    kept.deleteSync();
    Prefs.acceptedPackages =
        Prefs.acceptedPackages.where((p) => p != id).toList();
    // One that comes with the app would otherwise be offered again.
    Prefs.declinedPackages = [...Prefs.declinedPackages, id];
    if (books.isNotEmpty) {
      onProgress?.call('Updating the search index…');
      await DatabaseHelper().reindexBooks(books);
    }
  }

  static final _shippedName = RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)\.v(\d+)\.pkg\.db$');

  /// Puts the packages that come with the app in [folderName], where a copy
  /// is missing or older. Applying them is then [reapplyIfNeeded]'s work,
  /// the same as for one downloaded.
  ///
  /// This is how books reach every reader without a new database: the
  /// shipped databases stay as they are, and nothing is copied again but the
  /// package itself.
  static Future<void> placeShipped() => _placing ??= _placeShipped();
  static Future<void>? _placing;

  static Future<void> _placeShipped() async {
    final dir = folder(_dbDir);
    for (final name in AssetsFile.shippedPackages) {
      final m = _shippedName.firstMatch(name);
      if (m == null) {
        myLogger.e('shipped package $name is not named <id>.v<version>.pkg.db');
        continue;
      }
      final id = m.group(1)!;
      final version = int.parse(m.group(2)!);
      final kept = File(join(dir.path, '$id.db'));
      if (kept.existsSync()) {
        try {
          if ((await read(kept)).version >= version) continue;
        } catch (_) {
          // Unreadable: replaced below.
        }
      }
      try {
        dir.createSync(recursive: true);
        final data = await rootBundle.load(
            '${AssetsFile.baseAssetsFolderPath}/${AssetsFile.packagesFolderPath}/$name');
        final incoming = File(join(dir.path, '$id.part'));
        await incoming.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            flush: true);
        final info = await read(incoming);
        if (info.id != id || info.version != version) {
          incoming.deleteSync();
          myLogger.e('shipped package $name says it is '
              '${info.id} ${info.version}');
          continue;
        }
        await DatabaseHelper.runExclusive(() async {
          if (kept.existsSync()) kept.deleteSync();
          await incoming.rename(kept.path);
        });
        myLogger.i('shipped package $id $version put in place');
      } catch (e) {
        myLogger.e('shipped package $name not put in place: $e');
      }
    }
  }

  /// Packages that come with the app and are to be offered to the reader:
  /// not taken, not turned down, and not already in the database.
  static Future<List<PackageInfo>> offered() async {
    if (!DatabaseHelper.sentenceDataAvailable) return const [];
    await placeShipped();
    final shipped = {
      for (final name in AssetsFile.shippedPackages)
        _shippedName.firstMatch(name)?.group(1)
    };
    final db = await DatabaseHelper().database;
    final applied = <String>{};
    try {
      for (final r in await db.rawQuery('SELECT id FROM applied_package')) {
        applied.add(r['id'] as String);
      }
    } catch (_) {}
    return [
      for (final p in await installed())
        if (shipped.contains(p.id) &&
            !applied.contains(p.id) &&
            !Prefs.acceptedPackages.contains(p.id) &&
            !Prefs.declinedPackages.contains(p.id))
          p
    ];
  }

  /// Takes every package that comes with the app, unless the reader turned
  /// it down, so the next [reapplyIfNeeded] applies it without asking. For
  /// setup, which the reader is already waiting on.
  static void acceptShipped() {
    final ids = [
      for (final name in AssetsFile.shippedPackages)
        if (_shippedName.firstMatch(name)?.group(1) case final id?)
          if (!Prefs.declinedPackages.contains(id)) id
    ];
    Prefs.acceptedPackages = [...Prefs.acceptedPackages, ...ids];
  }

  /// The reader asked not to be offered [id] again.
  static void decline(String id) =>
      Prefs.declinedPackages = [...Prefs.declinedPackages, id];

  /// Applies again every kept package the databases no longer carry, after
  /// putting in place those that come with the app.
  ///
  /// Runs before the search index is built, so a database replaced by an
  /// update is indexed with its packages in it.
  static Future<void> reapplyIfNeeded(
      {void Function(String message)? onProgress}) async {
    if (!DatabaseHelper.sentenceDataAvailable) return;
    await placeShipped();
    final packages = await installed();
    if (packages.isEmpty) return;
    final db = await DatabaseHelper().database;
    final stamp = currentStamp();
    final applied = <String, (int, String)>{};
    try {
      for (final r in await db.rawQuery(
          'SELECT id, version, stamp FROM applied_package')) {
        applied[r['id'] as String] =
            ((r['version'] as int?) ?? 0, r['stamp'] as String? ?? '');
      }
    } catch (_) {
      // No table: nothing has been applied to this database.
    }

    final books = <String>[];
    for (final p in packages) {
      if (applied[p.id] == (p.version, stamp)) continue;
      // One that came with the app and was never taken waits to be offered;
      // see [offered]. Applied before (from before this was recorded)
      // counts as taken.
      if (!Prefs.acceptedPackages.contains(p.id)) {
        if (!applied.containsKey(p.id)) continue;
        Prefs.acceptedPackages = [...Prefs.acceptedPackages, p.id];
      }
      onProgress?.call('Applying ${p.title}…');
      try {
        books.addAll(await DatabaseHelper.runExclusive(
            () => run(db, p.file, stamp: stamp)));
        myLogger.i('package ${p.id} ${p.version} applied');
      } catch (e) {
        myLogger.e('package ${p.id} could not be applied: $e');
      }
    }
    if (books.isNotEmpty) await DatabaseHelper().reindexBooks(books);
  }
}

class PackageInfo {
  final String id;
  final int version;
  final String title;
  final String description;
  final File file;

  const PackageInfo({
    required this.id,
    required this.version,
    required this.title,
    required this.description,
    required this.file,
  });
}

class PackageException implements Exception {
  final String message;
  PackageException(this.message);
  @override
  String toString() => message;
}
