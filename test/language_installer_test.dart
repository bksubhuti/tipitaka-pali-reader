@Tags(['network'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:tipitaka_pali/services/language_installer.dart';

/// Exercises a real install, end to end, against the ePitaka releases.
///
/// Russian is the smallest published translation, about 10 MB, which makes it
/// the one worth downloading in a test. The point is not the language but the
/// path: download, unpack, keep only the sentences, throw the rest away.
///
/// Tagged `network` because it really does download. Run with:
///   flutter test test/language_installer_test.dart --tags network
void main() {
  late Directory scratch;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    scratch = Directory.systemTemp.createTempSync('tpr_lang_test');
    LanguageInstaller.directoryOverride = scratch.path;
  });

  tearDownAll(() {
    LanguageInstaller.directoryOverride = null;
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('installs Russian and keeps only the sentences', () async {
    const option = LanguageOption('ru', 'Russian');
    final messages = <String>[];

    await LanguageInstaller.install(option,
        onStep: (step, fraction, message) => messages.add(message));

    final installed = File(join(scratch.path, 'lang_ru.db'));
    expect(installed.existsSync(), isTrue, reason: 'the language file');

    // Nothing left behind: the download and the unpacked original are gone.
    expect(File(join(scratch.path, 'epitaka_ru.zip')).existsSync(), isFalse);
    expect(File(join(scratch.path, 'epitaka_ru.db')).existsSync(), isFalse);

    final db = await databaseFactory.openDatabase(installed.path);
    try {
      // Only the one table, and every row carries a translation.
      final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'");
      final names = tables.map((t) => t['name'] as String).toSet();
      expect(names, contains('sentences'));
      expect(names, isNot(contains('summaries')));
      expect(names, isNot(contains('translation_remarks')));

      final rows = await db.rawQuery('SELECT count(*) AS n FROM sentences');
      expect(rows.first['n'] as int, greaterThan(1000));

      final blanks = await db.rawQuery(
          "SELECT count(*) AS n FROM sentences "
          "WHERE translation IS NULL OR translation = ''");
      expect(blanks.first['n'], 0);

      // Keyed the way ePitaka keys its sentences, so it lines up with the Pali.
      final one = await db.rawQuery(
          'SELECT book_id, para_id, line_id, translation FROM sentences '
          'LIMIT 1');
      expect(one.first['book_id'], isA<String>());
      expect(one.first['para_id'], isA<int>());
      expect(one.first['line_id'], isA<int>());
      expect((one.first['translation'] as String).isNotEmpty, isTrue);
    } finally {
      await db.close();
    }

    expect(messages.last, contains('installed'));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
