import 'dart:io';

import 'package:archive/archive.dart';
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

  /// Installs [option], reporting progress as a fraction and a message.
  ///
  /// Leaves nothing behind on failure: a half-written language would attach
  /// and then answer no queries, which is worse than not having it.
  static Future<void> install(
    LanguageOption option, {
    void Function(double? progress, String message)? onProgress,
  }) async {
    final archive = File(join(_target, option.archiveName));
    final unpacked = File(join(_target, 'epitaka_${option.code}.db'));
    final target = File(join(_target, option.fileName));

    try {
      onProgress?.call(null, 'Downloading ${option.name}…');
      await _download('$releaseUrl/${option.archiveName}', archive,
          onProgress: onProgress);

      onProgress?.call(null, 'Unpacking ${option.name}…');
      await _unpack(archive, unpacked);
      await archive.delete();

      onProgress?.call(null, 'Preparing ${option.name}…');
      if (await target.exists()) await target.delete();
      await _copySentences(unpacked, target);
      await unpacked.delete();

      // Shown as well as installed. These are two different things in the
      // preferences, and leaving the second one out is why installing a
      // language beyond the first had no visible effect: the settings list
      // showed it, because that list appends whatever is installed, while the
      // reader asked the preference and never saw it.
      activate(option.code);

      onProgress?.call(null, '${option.name} installed');
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
  }

  /// Adds [code] to the languages shown beneath the Pali, keeping the order
  /// the reader has chosen and doing nothing if it is already there.
  static void activate(String code) {
    final active = [...Prefs.activeLanguages];
    if (active.contains(code)) return;
    Prefs.activeLanguages = [...active, code];
  }

  /// Removes an installed language.
  static Future<void> remove(String code) async {
    final file = File(join(_dir, 'lang_$code.db'));
    if (await file.exists()) await file.delete();
    Prefs.activeLanguages =
        Prefs.activeLanguages.where((c) => c != code).toList();
  }

  static Future<void> _download(
    String url,
    File target, {
    void Function(double? progress, String message)? onProgress,
  }) async {
    final response = await Dio().get<List<int>>(
      url,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          onProgress?.call(received / total,
              'Downloading… ${(received / total * 100).round()}%');
        }
      },
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: true,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    if (response.statusCode != 200 || response.data == null) {
      throw Exception('download failed with status ${response.statusCode}');
    }
    await target.writeAsBytes(response.data!);
  }

  static Future<void> _unpack(File archive, File target) async {
    final entries = ZipDecoder().decodeBytes(await archive.readAsBytes());
    for (final entry in entries) {
      if (!entry.isFile || entry.name.contains('__MACOSX')) continue;
      if (!entry.name.endsWith('.db')) continue;
      await target.writeAsBytes(entry.content as List<int>);
      return;
    }
    throw Exception('no database inside ${basename(archive.path)}');
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

  /// Reopens the databases so a newly installed language is picked up, and
  /// rebuilds the search index so it can be searched as well as read.
  static Future<void> applyChanges({
    void Function(double? progress, String message)? onProgress,
  }) async {
    onProgress?.call(null, 'Reloading…');
    await DatabaseHelper().close();
    await DatabaseHelper().database;
    await DatabaseHelper().buildSentenceFtsIfNeeded(
      onProgress: (message) => onProgress?.call(null, message),
    );
    // Search-as-you-type suggests words from the installed translations, so
    // that list has to follow a language being added or removed.
    await LegacyDataRetirement.buildTranslationWordList(
      await DatabaseHelper().database,
      onProgress: (message) => onProgress?.call(null, message),
    );
  }
}
