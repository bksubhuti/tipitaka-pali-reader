import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/database/legacy_data_retirement.dart';
import 'package:tipitaka_pali/services/prefs.dart';

/// A translation that can be installed.
class LanguageOption {
  /// The ePitaka code, e.g. 'en'.
  final String code;

  /// What to call it in the interface.
  final String name;

  const LanguageOption(this.code, this.name);

  String get fileName => 'lang_$code.db';
  String get archiveName => 'epitaka_$code.zip';
}

/// The stages of installing or removing a language, in order, so a screen
/// can show where it has got to rather than one message that never changes.
enum LanguageStep {
  download('Download'),
  unpack('Unpack'),
  prepare('Prepare'),
  attach('Open'),
  indexing('Index for search'),
  wordList('Search suggestions');

  final String label;
  const LanguageStep(this.label);

  /// The stages removing a language goes through.
  static const removal = [attach, indexing, wordList];
}

/// Reports a stage, a fraction where one is known, and a message.
typedef LanguageProgress = void Function(
    LanguageStep step, double? fraction, String message);

/// Downloads a translation from the ePitaka releases and installs it.
///
/// The published file carries far more than TPR needs: summaries, translation
/// remarks, confidence notes. Keeping only the sentences takes English from
/// 616 MB to 181 MB, so the download is unpacked, the sentences are copied
/// into a small database of their own, and the original is deleted. What
/// remains on the device is the translation and nothing else.
///
/// A language is then just a file. Installing one is this; removing one is
/// deleting the file. Neither requires rebuilding anything else, though the
/// search index is rebuilt so the new language can be searched.
class LanguageInstaller {
  LanguageInstaller._();

  /// Where the releases live. Rolling tag, so the newest is always here.
  static const releaseUrl =
      'https://github.com/dhammanana/epitaka_app/releases/download/latest';

  /// The translations ePitaka publishes.
  static const available = <LanguageOption>[
    LanguageOption('en', 'English'),
    LanguageOption('my', 'Myanmar'),
    LanguageOption('si', 'Sinhala'),
    LanguageOption('th', 'Thai'),
    LanguageOption('vi', 'Vietnamese'),
    LanguageOption('zh', 'Chinese'),
    LanguageOption('km', 'Khmer'),
    LanguageOption('lo', 'Lao'),
    LanguageOption('hi', 'Hindi'),
    LanguageOption('ru', 'Russian'),
    LanguageOption('pt', 'Portuguese'),
    LanguageOption('de', 'German'),
    LanguageOption('ja', 'Japanese'),
    LanguageOption('ta', 'Tamil'),
  ];

  static String get _dir => Prefs.databaseDirPath;

  /// Whether a language is already installed.
  static bool isInstalled(String code) =>
      File(join(_dir, 'lang_$code.db')).existsSync();

  /// Where language files live. Overridable so the install can be exercised
  /// against a scratch directory rather than the real one.
  @visibleForTesting
  static String? directoryOverride;

  static String get _target => directoryOverride ?? _dir;

  /// Installs [option] and makes it ready to read and search, reporting each
  /// stage as it goes.
  ///
  /// Leaves nothing behind on failure: a half-written language would attach
  /// and then answer no queries, which is worse than not having it.
  static Future<void> install(
    LanguageOption option, {
    LanguageProgress? onStep,
  }) async {
    final archive = File(join(_target, option.archiveName));
    final unpacked = File(join(_target, 'epitaka_${option.code}.db'));
    final target = File(join(_target, option.fileName));

    try {
      onStep?.call(LanguageStep.download, null, 'Downloading ${option.name}…');
      await _download('$releaseUrl/${option.archiveName}', archive,
          onProgress: (fraction, message) =>
              onStep?.call(LanguageStep.download, fraction, message));

      onStep?.call(LanguageStep.unpack, null, 'Unpacking ${option.name}…');
      await _unpack(archive, unpacked);
      await archive.delete();

      onStep?.call(LanguageStep.prepare, null, 'Preparing ${option.name}…');
      if (await target.exists()) await target.delete();
      await _copySentences(unpacked, target);
      await unpacked.delete();
    } catch (e) {
      debugPrint('installing ${option.code} failed: $e');
      for (final leftover in [archive, unpacked, target]) {
        if (await leftover.exists()) {
          try {
            await leftover.delete();
          } catch (_) {}
        }
      }
      rethrow;
    }

    if (directoryOverride != null) {
      // A test of the file work alone, against a scratch directory.
      onStep?.call(LanguageStep.prepare, 1, '${option.name} installed');
      return;
    }

    onStep?.call(LanguageStep.attach, null, 'Opening ${option.name}…');
    await DatabaseHelper().attachLanguage(option.code);
    // Shown as well as installed. These are two different things in the
    // preferences, and leaving the second one out is why installing a
    // language beyond the first had no visible effect.
    activate(option.code);

    await _reindex(onStep);
    onStep?.call(LanguageStep.wordList, 1, '${option.name} installed');
  }

  /// Brings search and the suggestions up to date with the installed set.
  ///
  /// Only the language that changed is indexed; the Pali index is left as it
  /// is. If a build started at launch is still running, this waits for it,
  /// and the message says so rather than sitting still.
  static Future<void> _reindex(LanguageProgress? onStep) async {
    void status() {
      final message = DatabaseHelper.indexStatus.value;
      if (message != null) onStep?.call(LanguageStep.indexing, null, message);
    }

    onStep?.call(LanguageStep.indexing, null, 'Indexing for search…');
    DatabaseHelper.indexStatus.addListener(status);
    try {
      await DatabaseHelper().buildSentenceFtsIfNeeded();
    } finally {
      DatabaseHelper.indexStatus.removeListener(status);
    }

    onStep?.call(LanguageStep.wordList, null, 'Updating search suggestions…');
    await LegacyDataRetirement.buildTranslationWordList(
      await DatabaseHelper().database,
      onProgress: (message) =>
          onStep?.call(LanguageStep.wordList, null, message),
    );
  }

  /// Adds [code] to the languages shown beneath the Pali, keeping the order
  /// the reader has chosen and doing nothing if it is already there.
  static void activate(String code) {
    // Best effort. The file is already written by the time this runs, and the
    // attach reconciles anything missing at the next open, so failing to
    // record the preference must not fail the install.
    try {
      final known = Prefs.knownLanguages;
      if (!known.contains(code)) Prefs.knownLanguages = [...known, code];
      final active = [...Prefs.activeLanguages];
      if (active.contains(code)) return;
      Prefs.activeLanguages = [...active, code];
    } catch (e) {
      debugPrint('could not record $code as shown: $e');
    }
  }

  /// Turns a language off without removing the file, or back on again.
  ///
  /// Off is not the same as gone: the download is kept, so a reader who wants
  /// the Pali alone for a while does not pay for it twice.
  static void setShown(String code, bool shown) {
    final active = [...Prefs.activeLanguages];
    if (!shown) {
      Prefs.activeLanguages = active.where((c) => c != code).toList();
      return;
    }
    if (active.contains(code)) return;
    // Back into its remembered place rather than onto the end, so switching
    // one off and on again does not reorder the page.
    final order = Prefs.knownLanguages;
    final wanted = [...active, code]
      ..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
    Prefs.activeLanguages = wanted;
  }

  /// Whether a language is being shown beneath the Pali.
  static bool isShown(String code) => Prefs.activeLanguages.contains(code);

  /// Removes an installed language, and takes it out of search.
  static Future<void> remove(String code, {LanguageProgress? onStep}) async {
    onStep?.call(LanguageStep.attach, null, 'Closing $code…');
    // Detached first: an attached file cannot be deleted on Windows, and on
    // the others deleting it underneath an open connection leaves queries
    // answering from a file that is no longer there.
    await DatabaseHelper().detachLanguage(code);
    final file = File(join(_dir, 'lang_$code.db'));
    if (await file.exists()) await file.delete();
    Prefs.activeLanguages =
        Prefs.activeLanguages.where((c) => c != code).toList();
    // Forgotten as well as removed, so installing it again offers it afresh
    // rather than treating it as one that was switched off.
    Prefs.knownLanguages =
        Prefs.knownLanguages.where((c) => c != code).toList();
    await _reindex(onStep);
    onStep?.call(LanguageStep.wordList, 1, 'Removed');
  }

  /// Streams the download to disk. Held in memory, the larger languages are
  /// well over a hundred megabytes, which a low-end phone may not have to
  /// spare.
  static Future<void> _download(
    String url,
    File target, {
    void Function(double? progress, String message)? onProgress,
  }) async {
    final response = await Dio().download(
      url,
      target.path,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          onProgress?.call(received / total,
              'Downloading… ${(received / total * 100).round()}%');
        }
      },
      options: Options(
        followRedirects: true,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    if (response.statusCode != 200) {
      throw Exception('download failed with status ${response.statusCode}');
    }
  }

  /// Unpacks the database out of the archive, in a background isolate and a
  /// piece at a time.
  ///
  /// Decoded whole on the main isolate, the English archive became 600 MB in
  /// memory and the screen stopped answering until it was done, which on a
  /// phone looks the same as a crash.
  static Future<void> _unpack(File archive, File target) async {
    final source = archive.path;
    final destination = target.path;
    final found = await Isolate.run(() {
      final input = InputFileStream(source);
      try {
        final entries = ZipDecoder().decodeBuffer(input);
        for (final entry in entries) {
          if (!entry.isFile || entry.name.contains('__MACOSX')) continue;
          if (!entry.name.endsWith('.db')) continue;
          final output = OutputFileStream(destination);
          try {
            entry.writeContent(output);
          } finally {
            output.closeSync();
          }
          return true;
        }
        return false;
      } finally {
        input.closeSync();
      }
    });
    if (!found) {
      throw Exception('no database inside ${basename(archive.path)}');
    }
  }

  /// Copies just the translated sentences into a database of their own.
  static Future<void> _copySentences(File source, File target) async {
    final db = await openDatabase(target.path);
    try {
      await db.execute('''
        CREATE TABLE sentences (
          book_id TEXT NOT NULL,
          para_id INTEGER NOT NULL,
          line_id INTEGER NOT NULL,
          translation TEXT,
          PRIMARY KEY (book_id, para_id, line_id)
        ) WITHOUT ROWID
      ''');
      await db.execute('ATTACH DATABASE ? AS src', [source.path]);
      await db.execute('''
        INSERT INTO sentences (book_id, para_id, line_id, translation)
        SELECT book_id, para_id, line_id, translation FROM src.sentences
        WHERE translation IS NOT NULL AND translation <> ''
      ''');
      await db.execute('DETACH DATABASE src');
    } finally {
      await db.close();
    }
  }
}
