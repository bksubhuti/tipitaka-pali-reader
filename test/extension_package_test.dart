@TestOn('windows || linux || mac-os')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:tipitaka_pali/services/database/sentence_fts_builder.dart';
import 'package:tipitaka_pali/services/extensions/extension_packages.dart';

/// A package goes in whole or not at all, can be applied again without
/// doubling anything, comes out cleanly, and leaves search matching what the
/// reader can open.
void main() {
  late Database db;
  late Directory temp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pkg_test');
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await db.execute('CREATE TABLE books (id TEXT PRIMARY KEY, basket TEXT, '
        'category NUMERIC, name TEXT, firstpage INTEGER, lastpage INTEGER, '
        'pagecount INTEGER, sort_order INTEGER DEFAULT 0)');
    await db.execute("ATTACH DATABASE ':memory:' AS epi");
    await db.execute("ATTACH DATABASE ':memory:' AS ext");
    await db.execute('CREATE TABLE epi.sentences (book_id TEXT, '
        'para_id INTEGER, line_id INTEGER, vripara TEXT, pali TEXT)');
    await db.execute('CREATE TABLE ext.page_break (book_id TEXT NOT NULL, '
        'para_id INTEGER NOT NULL, line_id INTEGER NOT NULL, '
        'tpr_book TEXT NOT NULL, tpr_page INTEGER NOT NULL, '
        'word_index INTEGER NOT NULL, exact INTEGER NOT NULL)');

    final batch = db.batch();
    for (final book in ['Old', 'New']) {
      for (var para = 1; para <= 30; para++) {
        batch.rawInsert('INSERT INTO epi.sentences VALUES (?, ?, 1, ?, ?)', [
          book, para, '$para',
          book == 'New'
              ? 'mohavicchedanī kiñcāpi khīṇāsavānaṃ $para'
              : 'evaṃ me sutaṃ ekaṃ samayaṃ $para'
        ]);
      }
    }
    // Only the old book has pages; the new one is what the package adds.
    batch.insert('books', {'id': 'old_01', 'name': 'old'});
    for (var para = 1; para <= 30; para += 3) {
      batch.rawInsert('INSERT INTO ext.page_break VALUES (?,?,1,?,?,0,1)',
          ['Old', para, 'old_01', para]);
    }
    await batch.commit(noResult: true);
    await SentenceFtsBuilder.build(db);
  });

  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  /// A package adding the book `New` as `new_01`, ten pages of three
  /// paragraphs. [extra] steps run after the copies.
  Future<File> package(
      {int format = 1,
      int pageEvery = 3,
      List<(String, String?, String)> extra = const []}) async {
    final file = File(join(
        temp.path, 'p${extra.length}_${format}_$pageEvery.pkg.db'));
    final p = await databaseFactoryFfi.openDatabase(file.path);
    await p.execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)');
    await p.execute('CREATE TABLE commands (seq INTEGER PRIMARY KEY, '
        "phase TEXT NOT NULL DEFAULT 'install', op TEXT NOT NULL, "
        'target TEXT, arg TEXT)');
    await p.execute('CREATE TABLE books (id TEXT, basket TEXT, '
        'category NUMERIC, name TEXT, firstpage INTEGER, lastpage INTEGER, '
        'pagecount INTEGER, sort_order INTEGER, not_in_main TEXT)');
    await p.execute('CREATE TABLE page_break (book_id TEXT, para_id INTEGER, '
        'line_id INTEGER, tpr_book TEXT, tpr_page INTEGER, '
        'word_index INTEGER, exact INTEGER)');
    for (final (k, v) in [
      ('id', 'test_pkg'),
      ('version', '1'),
      ('title', 'Test'),
      ('format', '$format'),
    ]) {
      await p.insert('meta', {'key': k, 'value': v});
    }
    await p.insert('books', {
      'id': 'new_01', 'basket': 'tika', 'category': 'bi', 'name': 'new',
      'firstpage': 1, 'lastpage': 10, 'pagecount': 10, 'not_in_main': 'x'
    });
    var page = 0;
    for (var para = 1; para <= 30; para += pageEvery) {
      await p.insert('page_break', {
        'book_id': 'New', 'para_id': para, 'line_id': 1,
        'tpr_book': 'new_01', 'tpr_page': ++page, 'word_index': 0,
        'exact': 1
      });
    }
    final clear = [
      ('sql', null, "DELETE FROM main.books WHERE id = 'new_01'"),
      ('sql', null, "DELETE FROM ext.page_break WHERE tpr_book = 'new_01'"),
    ];
    final steps = [
      for (final c in clear) ('install', c.$1, c.$2, c.$3),
      ('install', 'copy', 'main.books', 'books'),
      ('install', 'copy', 'ext.page_break', 'page_break'),
      for (final e in extra) ('install', e.$1, e.$2, e.$3),
      ('install', 'reindex', null, 'New'),
      for (final c in clear) ('remove', c.$1, c.$2, c.$3),
      ('remove', 'reindex', null, 'New'),
    ];
    for (final (phase, op, target, arg) in steps) {
      await p.insert('commands',
          {'phase': phase, 'op': op, 'target': target, 'arg': arg});
    }
    await p.close();
    return file;
  }

  Future<int> count(String sql) async =>
      (await db.rawQuery(sql)).first.values.first as int;

  Future<List<String>> hits(String word) async => [
        for (final r in await db.rawQuery(
            'SELECT u.bookid FROM fts_unit f JOIN search_unit u '
            'ON u.id = f.rowid JOIN books ON books.id = u.bookid '
            'WHERE fts_unit MATCH ?',
            [word]))
          r['bookid'] as String
      ];

  Future<void> install(File file) async {
    final books = await ExtensionPackages.run(db, file, stamp: 's1');
    await SentenceFtsBuilder.reindexBooks(db, books);
  }

  test('installs the book, its pages and its search', () async {
    expect(await hits('mohavicchedanī'), isEmpty);
    await install(await package());

    expect(await count("SELECT count(*) FROM books WHERE id = 'new_01'"), 1);
    expect(
        await count(
            "SELECT count(*) FROM ext.page_break WHERE tpr_book = 'new_01'"),
        10);
    expect(await hits('mohavicchedanī'), isNotEmpty);
    expect((await hits('mohavicchedanī')).toSet(), {'new_01'});
    expect(await hits('sutaṃ'), isNotEmpty, reason: 'old book still found');
    expect(await SentenceFtsBuilder.isBuilt(db), isTrue,
        reason: 'a partial reindex must not make the index look unfinished');
    expect(
        await db.rawQuery('SELECT id, version, stamp FROM applied_package'),
        [
          {'id': 'test_pkg', 'version': 1, 'stamp': 's1'}
        ]);
  });

  test('applying twice leaves one copy of everything', () async {
    final file = await package();
    await install(file);
    final units = await db.rawQuery(
        "SELECT id, page FROM search_unit WHERE epi_book = 'New' ORDER BY id");
    await install(file);

    expect(await count("SELECT count(*) FROM books WHERE id = 'new_01'"), 1);
    expect(
        await count(
            "SELECT count(*) FROM ext.page_break WHERE tpr_book = 'new_01'"),
        10);
    expect(
        await db.rawQuery("SELECT id, page FROM search_unit "
            "WHERE epi_book = 'New' ORDER BY id"),
        units,
        reason: 'same text, same units: rewritten in place');
    expect((await hits('mohavicchedanī')).length, units.length);
  });

  test('new pages move search results to the new pages', () async {
    await install(await package());
    // A second release pages the book every 5 paragraphs instead of 3.
    final file = await package(pageEvery: 5);
    final books = await ExtensionPackages.run(db, file);
    await SentenceFtsBuilder.reindexBooks(db, books);

    final last = await db.rawQuery("SELECT max(page) AS p FROM search_unit "
        "WHERE epi_book = 'New'");
    expect(last.first['p'], lessThanOrEqualTo(6));
  });

  test('remove takes the book out of the library and search', () async {
    final file = await package();
    await install(file);
    final books = await ExtensionPackages.run(db, file, phase: 'remove');
    await SentenceFtsBuilder.reindexBooks(db, books);

    expect(await count("SELECT count(*) FROM books WHERE id = 'new_01'"), 0);
    expect(
        await count(
            "SELECT count(*) FROM ext.page_break WHERE tpr_book = 'new_01'"),
        0);
    expect(await hits('mohavicchedanī'), isEmpty);
    expect(await hits('sutaṃ'), isNotEmpty);
    expect(await SentenceFtsBuilder.isBuilt(db), isTrue);
    expect(await count('SELECT count(*) FROM applied_package'), 0);

    // And in again: new units are numbered past the ones left behind.
    await install(file);
    expect(await hits('mohavicchedanī'), isNotEmpty);
  });

  test('a step that fails leaves nothing behind', () async {
    final file = await package(extra: [('sql', null, 'DELETE FROM nowhere')]);
    await expectLater(ExtensionPackages.run(db, file), throwsA(anything));

    expect(await count("SELECT count(*) FROM books WHERE id = 'new_01'"), 0);
    expect(
        await count(
            "SELECT count(*) FROM ext.page_break WHERE tpr_book = 'new_01'"),
        0);
    // Not left attached either.
    await install(await package());
  });

  test('an unknown step is refused before anything runs', () async {
    final file = await package(extra: [('shell', null, 'rm -rf /')]);
    await expectLater(
        ExtensionPackages.run(db, file), throwsA(isA<PackageException>()));
    expect(await count("SELECT count(*) FROM books WHERE id = 'new_01'"), 0);
  });

  test('a copy into anything but main or ext is refused', () async {
    final file = await package(extra: [('copy', 'epi.sentences', 'books')]);
    await expectLater(
        ExtensionPackages.run(db, file), throwsA(isA<PackageException>()));
  });

  test('a package for a newer app is refused', () async {
    final file = await package(format: ExtensionPackages.supportedFormat + 1);
    await expectLater(
        ExtensionPackages.run(db, file), throwsA(isA<PackageException>()));
  });
}
