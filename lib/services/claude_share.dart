import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:tipitaka_pali/app.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/prefs.dart';

/// Shares TPR's books and the reader's history with the TPR Research
/// extension in Claude Desktop, on the Mac.
///
/// The Mac app is sandboxed, and macOS will not let Claude's extension read
/// the sandbox's files. So TPR keeps a copy in ~/TPR/db, a plain folder
/// Claude reads without asking: the books, copied again only when they change
/// (on APFS a copy is a clone, instant and taking no space), and a small
/// history.db of pages opened, searches and look-ups, written whenever the app
/// goes to the background and every few minutes while it is open.
///
/// The reader turns it on by installing the extension (type "skill" in the
/// script converter); until then this does nothing.
class ClaudeShare {
  static const _channel = MethodChannel('tpr/folder_access');
  static const _folder = 'tpr';
  static const _stampPref = 'claudeShareStamp';

  static bool get _supported => Platform.isMacOS || Platform.isWindows;

  /// On Windows ~/TPR needs no permission; this records that the reader
  /// set Claude up, so the copy is kept only for them (it takes the books'
  /// space again: Windows cannot clone a file as APFS does).
  static const _windowsPref = 'claudeShareWindows';

  /// ~/TPR, opened for writing; null if the reader never set Claude up.
  static Future<String?> _open() async {
    if (Platform.isWindows) {
      if (!(Prefs.instance.getBool(_windowsPref) ?? false)) return null;
      return p.join(Platform.environment['USERPROFILE'] ?? '', 'TPR');
    }
    return _channel.invokeMethod<String>('start', {'name': _folder});
  }

  static Future<void> _close() async {
    if (Platform.isMacOS) {
      await _channel.invokeMethod('stop', {'name': _folder});
    }
  }

  static Timer? _timer;
  static Future<void>? _running;

  /// The reader's real home folder; in the sandbox HOME is the container.
  static String get realHome {
    final home = Platform.environment['HOME'] ?? '';
    final i = home.indexOf('/Library/Containers/');
    return i > 0 ? home.substring(0, i) : home;
  }

  /// macOS's folder picker, opened on [directory], with its own [button].
  static Future<String?> pickFolder(
      {required String directory,
      required String button,
      required String message}) async {
    if (!Platform.isMacOS) return null;
    return _channel.invokeMethod<String>(
        'pick', {'directory': directory, 'button': button, 'message': message});
  }

  /// Remembers ~/TPR (just picked by the reader), so it stays writable.
  static Future<void> remember(String tprDir) async {
    if (Platform.isWindows) {
      await Prefs.instance.setBool(_windowsPref, true);
      return;
    }
    if (!_supported) return;
    await _channel.invokeMethod('remember', {'name': _folder, 'path': tprDir});
  }

  /// The TPR Research version when the extension is set up in Claude
  /// Desktop (or, with [host], in that app: 'codex', 'antigravity'), else null. The extension writes ~/TPR/.tpr-research each time
  /// Claude starts it; a note a month old or more is taken as removed.
  static Future<String?> extensionVersion({String? host}) async {
    if (!Platform.isMacOS && !Platform.isWindows) return null;
    String? tpr;
    var opened = false;
    try {
      if (Platform.isMacOS) {
        tpr = await _channel.invokeMethod<String>('start', {'name': _folder});
        if (tpr == null) return null; // never set up
        opened = true;
      } else {
        tpr = p.join(Platform.environment['USERPROFILE'] ?? '', 'TPR');
      }
      // Other apps start the same server with TPR_HOST=<host>, which
      // writes its own note.
      final note = File(p.join(
          tpr, host == null ? '.tpr-research' : '.tpr-research-$host'));
      if (!note.existsSync()) return null;
      final data = jsonDecode(await note.readAsString()) as Map;
      final seen = DateTime.tryParse('${data['seen']}');
      if (seen == null ||
          DateTime.now().difference(seen) > const Duration(days: 30)) {
        return null;
      }
      return '${data['version'] ?? ''}';
    } catch (e) {
      myLogger.e('Claude share: no extension note: $e');
      return null;
    } finally {
      if (opened) await _channel.invokeMethod('stop', {'name': _folder});
    }
  }

  /// Keeps the copy current from now on, if the reader set it up.
  static void start() {
    if (!_supported || _timer != null) return;
    // The books are checked too: cheap when unchanged, and it catches the
    // search index finishing or a translation added.
    _timer =
        Timer.periodic(const Duration(minutes: 5), (_) => refresh(books: true));
    // Lives as long as the app; it registers itself with the binding.
    AppLifecycleListener(
      onHide: refresh,
      onExitRequested: () async {
        await refresh();
        return AppExitResponse.exit;
      },
    );
    // After start-up has settled, so the copy never slows the first page.
    Future.delayed(const Duration(seconds: 30), () => refresh(books: true));
  }

  /// Writes the history, and the books too when [books] and they changed.
  static Future<void> refresh({bool books = false}) async {
    if (!_supported) return;
    // One at a time: a request made during a copy waits for it, then runs.
    while (_running != null) {
      await _running;
    }
    final run = _refresh(books: books);
    _running = run;
    try {
      await run;
    } finally {
      _running = null;
    }
  }

  static Future<void> _refresh({required bool books}) async {
    String? tpr;
    try {
      tpr = await _open();
      if (tpr == null) return; // never set up
      final db = Directory(p.join(tpr, 'db'));
      await db.create(recursive: true);
      if (books) await _copyBooks(db.path);
      await _writeHistory(db.path);
    } catch (e) {
      myLogger.e('Claude share: $e');
    } finally {
      if (tpr != null) await _close();
    }
  }

  /// What the copy depends on: the database version, the search index and
  /// the translations. History is left out; it goes in history.db.
  static Future<String?> _stamp(Database main) async {
    if (!DatabaseHelper.sentenceSearchAvailable) return null; // not ready
    final meta = await main.rawQuery(
        "SELECT key, value FROM search_meta WHERE key IN ('units','format','languages','translation_format') "
        'ORDER BY key');
    final langs = DatabaseHelper.installedLanguages.map((code) {
      final f = File(p.join(Prefs.databaseDirPath, 'lang_$code.db'));
      return '$code:${f.existsSync() ? f.lengthSync() : 0}';
    }).join(',');
    final epi = File(p.join(Prefs.databaseDirPath, 'epitaka.db'));
    return [
      Prefs.databaseVersion,
      ...meta.map((r) => '${r['key']}=${r['value']}'),
      'epi:${epi.existsSync() ? epi.lengthSync() : 0}',
      langs,
    ].join('|');
  }

  static Future<void> _copyBooks(String to) async {
    final main = await DatabaseHelper().database;
    final stamp = await _stamp(main);
    if (stamp == null) return;
    final have = File(p.join(to, 'tipitaka_pali.db')).existsSync();
    if (have && Prefs.instance.getString(_stampPref) == stamp) return;
    final from = Prefs.databaseDirPath;
    final names = [
      'tipitaka_pali.db',
      'epitaka.db',
      for (final code in DatabaseHelper.installedLanguages) 'lang_$code.db',
    ];
    for (final name in names) {
      final source = File(p.join(from, name));
      if (!source.existsSync()) continue;
      // Copied beside, then renamed over, so Claude never reads half a file.
      final part = p.join(to, '$name.part');
      await source.copy(part);
      await File(part).rename(p.join(to, name));
    }
    // A translation removed in TPR goes from the copy too.
    for (final f in Directory(to).listSync().whereType<File>()) {
      final name = p.basename(f.path);
      if (name.startsWith('lang_') &&
          name.endsWith('.db') &&
          !names.contains(name)) {
        await f.delete();
      }
    }
    await Prefs.instance.setString(_stampPref, stamp);
    myLogger.i('Claude share: books copied to $to');
  }

  static Future<void> _writeHistory(String to) async {
    final main = await DatabaseHelper().database;
    final recent = await main
        .rawQuery('SELECT book_id, page_number FROM recent ORDER BY rowid');
    final searches = await main
        .rawQuery('SELECT word, date, query_mode FROM search_history');
    final words = await main.rawQuery(
        'SELECT word, context, date, book_id, page_number FROM dictionary_history');
    final part = p.join(to, 'history.db.part');
    final old = File(part);
    if (old.existsSync()) await old.delete();
    final db = await openDatabase(part);
    try {
      await db.transaction((t) async {
        await t
            .execute('CREATE TABLE recent (book_id TEXT, page_number INTEGER)');
        await t.execute(
            'CREATE TABLE search_history (word TEXT, date TEXT, query_mode INTEGER)');
        await t.execute('CREATE TABLE dictionary_history '
            '(word TEXT, context TEXT, date TEXT, book_id TEXT, page_number INTEGER)');
        final b = t.batch();
        for (final r in recent) {
          b.insert('recent', r);
        }
        for (final r in searches) {
          b.insert('search_history', r);
        }
        for (final r in words) {
          b.insert('dictionary_history', r);
        }
        await b.commit(noResult: true);
      });
    } finally {
      await db.close();
    }
    await File(part).rename(p.join(to, 'history.db'));
  }
}
