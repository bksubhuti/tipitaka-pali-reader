@TestOn('windows || linux || mac-os')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:tipitaka_pali/services/database/sentence_fts_builder.dart';

/// The search index cleans its text with a quick loop instead of two
/// patterns, which were most of the time a build took. Text cleaned even
/// slightly differently would change what search finds without any sign, so
/// this compares the new reading against the old, written out here as it
/// was, sentence by sentence and paragraph by paragraph, for every book.
///
/// The small cases run always. The whole canon runs when the real data is at
/// hand: point TPR_DATA_DIR at a folder holding `epitaka.db` and any
/// `lang_<code>.db` files.
void main() {
  setUpAll(sqfliteFfiInit);

  Future<Database> open() => databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false));

  /// How the index read a book before: each sentence through the patterns,
  /// empty ones dropped, the rest joined with a space within a paragraph.
  Future<List<(int, String)>> readAsBefore(
      Database db, String table, String column, String book) async {
    final rows = await db.rawQuery(
        'SELECT para_id, $column AS text FROM $table WHERE book_id = ? '
        'ORDER BY para_id, line_id',
        [book]);
    final paragraphs = <int, StringBuffer>{};
    final order = <int>[];
    for (final row in rows) {
      final para = row['para_id'] as int;
      final text =
          SentenceFtsBuilder.cleanByPattern(row['text'] as String? ?? '');
      if (text.isEmpty) continue;
      final buffer = paragraphs.putIfAbsent(para, () {
        order.add(para);
        return StringBuffer();
      });
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(text);
    }
    return [for (final para in order) (para, paragraphs[para].toString())];
  }

  Future<void> expectSame(Database db, String table, String column) async {
    final books = (await db
            .rawQuery('SELECT DISTINCT book_id FROM $table ORDER BY book_id'))
        .map((r) => r['book_id'] as String)
        .toList();
    expect(books, isNotEmpty);
    var paragraphs = 0;
    for (final book in books) {
      final read =
          await SentenceFtsBuilder.readParagraphs(db, table, column, book);
      final before = await readAsBefore(db, table, column, book);
      expect(read.length, before.length, reason: '$table $book');
      for (var i = 0; i < read.length; i++) {
        if (read[i] != before[i]) {
          fail('$table $book paragraph ${before[i].$1} differs:\n'
              'now:    ${read[i]}\nbefore: ${before[i]}');
        }
      }
      paragraphs += read.length;
    }
    // Every sentence, not only the paragraphs they make.
    var sentences = 0;
    for (final book in books) {
      final rows = await db.rawQuery(
          'SELECT $column AS text FROM $table WHERE book_id = ?', [book]);
      for (final row in rows) {
        final text = row['text'] as String? ?? '';
        final quick = SentenceFtsBuilder.clean(text);
        if (quick != SentenceFtsBuilder.cleanByPattern(text)) {
          fail('$table $book cleans differently: $text');
        }
        sentences++;
      }
    }
    // ignore: avoid_print
    print('$table: ${books.length} books, $paragraphs paragraphs and '
        '$sentences sentences identical');
  }

  test('lines join in line order, whatever order they were stored in',
      () async {
    final db = await open();
    await db.execute('CREATE TABLE s (book_id TEXT, para_id INTEGER, '
        'line_id INTEGER, pali TEXT)');
    // Stored out of order on purpose.
    for (final row in [
      ['b', 2, 3, 'three'],
      ['b', 1, 2, 'second'],
      ['b', 2, 1, 'one'],
      ['b', 1, 1, 'first'],
      ['b', 2, 2, 'two'],
    ]) {
      await db.rawInsert('INSERT INTO s VALUES (?, ?, ?, ?)', row);
    }
    final read = await SentenceFtsBuilder.readParagraphs(db, 's', 'pali', 'b');
    expect(read, [(1, 'first second'), (2, 'one two three')]);
    await expectSame(db, 's', 'pali');
    await db.close();
  });

  test('empty, null, tag-only and spaced sentences read as they did',
      () async {
    final db = await open();
    await db.execute('CREATE TABLE s (book_id TEXT, para_id INTEGER, '
        'line_id INTEGER, pali TEXT)');
    for (final row in [
      ['b', 1, 1, null],
      ['b', 1, 2, ''],
      ['b', 1, 3, '  evaṃ   me '],
      ['b', 1, 4, '<b></b>'],
      ['b', 1, 5, 'sutaṃ<br/>ekaṃ'],
      ['b', 2, 1, ''],
      ['b', 2, 2, null],
      ['b', 3, 1, '<i>samayaṃ</i>'],
    ]) {
      await db.rawInsert('INSERT INTO s VALUES (?, ?, ?, ?)', row);
    }
    final read = await SentenceFtsBuilder.readParagraphs(db, 's', 'pali', 'b');
    // Paragraph 2 has no text and is left out, as it always was.
    expect(read, [(1, 'evaṃ me sutaṃ ekaṃ'), (3, 'samayaṃ')]);
    await expectSame(db, 's', 'pali');
    await db.close();
  });

  test('the quick check cleans exactly as the patterns do', () {
    for (final text in [
      '',
      ' ',
      'evaṃ',
      'evaṃ me sutaṃ',
      ' evaṃ',
      'evaṃ ',
      'evaṃ  me',
      'evaṃ\tme',
      'evaṃ\nme',
      'evaṃ\u00a0me',
      'evaṃ\u2003me',
      'evaṃ\ufeffme',
      '<b>evaṃ</b>',
      'a < b',
      'a <b',
      '<br/>',
      '<a>x<b>y</b>z',
      'x<<b>>y',
      '<\n>x',
      'x<br>\u0085',
      '\u0085x',
      '\u3000',
    ]) {
      expect(SentenceFtsBuilder.clean(text),
          SentenceFtsBuilder.cleanByPattern(text),
          reason: 'for ${text.codeUnits}');
    }
  });

  final dataDir = Platform.environment['TPR_DATA_DIR'];
  final hasData =
      dataDir != null && File(join(dataDir, 'epitaka.db')).existsSync();

  test('every book of the real data reads as it did', () async {
    final db = await open();
    await db.execute(
        'ATTACH DATABASE ? AS epi', [join(dataDir!, 'epitaka.db')]);
    await expectSame(db, 'epi.sentences', 'pali');

    final languages = Directory(dataDir)
        .listSync()
        .whereType<File>()
        .map((f) => basename(f.path))
        .where((n) => n.startsWith('lang_') && n.endsWith('.db'))
        .toList()
      ..sort();
    for (final name in languages) {
      final code = name.substring(5, name.length - 3);
      await db.execute(
          'ATTACH DATABASE ? AS lang_$code', [join(dataDir, name)]);
      await expectSame(db, 'lang_$code.sentences', 'translation');
    }
    await db.close();
  },
      skip: hasData ? false : 'set TPR_DATA_DIR to run against the real data',
      timeout: const Timeout(Duration(minutes: 20)));
}
