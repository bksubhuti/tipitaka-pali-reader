@TestOn('windows || linux || mac-os')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/database/legacy_data_retirement.dart';

/// A language file can be on the device and still not be whole: an install
/// cut off part way, or a reset that kept the file but started a fresh
/// database without its words. Both looked installed. These check that the
/// app goes by what was actually completed.
void main() {
  late Database db;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await db.execute('CREATE TABLE words (word TEXT COLLATE NOCASE, '
        'plain TEXT COLLATE NOCASE, frequency INTEGER)');
    await db.execute('CREATE UNIQUE INDEX word_unique_index ON words (word)');
    await db.execute("INSERT INTO words VALUES ('dhamma', 'dhamma', 900)");
  });

  tearDown(() async {
    DatabaseHelper.installedLanguages = const [];
    await db.close();
  });

  Future<void> addLanguage(String code,
      {List<String> lines = const [], bool? complete}) async {
    await db.execute("ATTACH DATABASE ':memory:' AS lang_$code");
    await db.execute('CREATE TABLE lang_$code.sentences (book_id TEXT, '
        'para_id INTEGER, line_id INTEGER, translation TEXT)');
    for (var i = 0; i < lines.length; i++) {
      await db.rawInsert('INSERT INTO lang_$code.sentences VALUES (?, ?, ?, ?)',
          ['b', 1, i + 1, lines[i]]);
    }
    if (complete != null) {
      await db.execute(
          'CREATE TABLE lang_$code.meta (key TEXT PRIMARY KEY, value TEXT)');
      if (complete) {
        await db.execute(
            "INSERT INTO lang_$code.meta VALUES ('complete', '1')");
      }
    }
  }

  Future<List<String>> translationWords() async =>
      (await db.rawQuery(
              'SELECT word FROM words WHERE frequency = -1 ORDER BY word'))
          .map((r) => r['word'] as String)
          .toList();

  group('a language file is whole', () {
    test('when it has sentences and finished installing', () async {
      await addLanguage('en', lines: ['Thus have I heard'], complete: true);
      expect(await DatabaseHelper.languageComplete(db, 'en'), isTrue);
    });

    test('when it has sentences and is from before the record', () async {
      await addLanguage('en', lines: ['Thus have I heard']);
      expect(await DatabaseHelper.languageComplete(db, 'en'), isTrue);
    });

    test('not when its sentences table is empty', () async {
      await addLanguage('en');
      expect(await DatabaseHelper.languageComplete(db, 'en'), isFalse);
    });

    test('not when the install never wrote its finishing mark', () async {
      await addLanguage('en', lines: ['Thus have I heard'], complete: false);
      expect(await DatabaseHelper.languageComplete(db, 'en'), isFalse);
    });

    test('unknown, not incomplete, when it cannot be read', () async {
      // Nothing attached under this name: no grounds to remove anything.
      expect(await DatabaseHelper.languageComplete(db, 'xx'), isNull);
    });
  });

  group('translation words follow what is installed', () {
    test('a language on the device without its words gets them', () async {
      await addLanguage('en',
          lines: ['Thus have I heard', 'the Blessed One'], complete: true);
      DatabaseHelper.installedLanguages = ['en'];

      await LegacyDataRetirement.ensureTranslationWordLists(db);
      expect(await translationWords(),
          ['blessed', 'have', 'heard', 'one', 'the', 'thus']);

      // Done once: a second start finds it recorded and adds nothing.
      await db.rawDelete("DELETE FROM words WHERE word = 'thus'");
      await LegacyDataRetirement.ensureTranslationWordLists(db);
      expect(await translationWords(), isNot(contains('thus')));
    });

    test('the Pali keeps its own entry when a word is in both', () async {
      await addLanguage('en', lines: ['dhamma and more'], complete: true);
      DatabaseHelper.installedLanguages = ['en'];
      await LegacyDataRetirement.ensureTranslationWordLists(db);
      final rows = await db
          .rawQuery("SELECT frequency FROM words WHERE word = 'dhamma'");
      expect(rows.single['frequency'], 900);
    });

    test('a removed language takes its words with it', () async {
      await addLanguage('en', lines: ['Thus have I heard'], complete: true);
      await addLanguage('de', lines: ['So habe ich gehört'], complete: true);
      DatabaseHelper.installedLanguages = ['de', 'en'];
      await LegacyDataRetirement.ensureTranslationWordLists(db);
      expect(await translationWords(), containsAll(['heard', 'habe']));

      DatabaseHelper.installedLanguages = ['de'];
      await LegacyDataRetirement.ensureTranslationWordLists(db);
      final words = await translationWords();
      expect(words, contains('habe'));
      expect(words, isNot(contains('heard')));

      DatabaseHelper.installedLanguages = [];
      await LegacyDataRetirement.ensureTranslationWordLists(db);
      expect(await translationWords(), isEmpty);
      // The Pali is untouched throughout.
      expect(
          (await db.rawQuery("SELECT word FROM words WHERE frequency > 0"))
              .single['word'],
          'dhamma');
    });

    test('languages without Latin words are left alone', () async {
      await addLanguage('my', lines: ['ဤသို့'], complete: true);
      DatabaseHelper.installedLanguages = ['my'];
      await LegacyDataRetirement.ensureTranslationWordLists(db);
      expect(await translationWords(), isEmpty);
    });
  });
}
