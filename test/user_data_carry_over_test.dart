@TestOn('windows || linux || mac-os')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:tipitaka_pali/services/database/user_data_carry_over.dart';

/// An update replaces the database; the reader's own data has to come across.
///
/// It used to be the bookmarks alone, so folders, recents, history and the
/// dictionary order were lost at every update, and bookmarks kept pointing at
/// folders that were gone.
void main() {
  setUpAll(sqfliteFfiInit);

  Future<Database> open() => databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false));

  Future<void> schema(Database db, {bool newColumn = false}) async {
    await db.execute('CREATE TABLE folder (id INTEGER PRIMARY KEY '
        'AUTOINCREMENT, name TEXT NOT NULL, parent_folder_id INTEGER '
        'DEFAULT -1)');
    await db.execute('CREATE TABLE bookmark (id INTEGER PRIMARY KEY '
        'AUTOINCREMENT, book_id TEXT NOT NULL, page_number INTEGER NOT NULL, '
        'note TEXT, name TEXT NOT NULL, selected_text TEXT, folder_id INTEGER '
        'DEFAULT -1, bmk_sort INTEGER DEFAULT -1'
        '${newColumn ? ', color TEXT' : ''})');
    await db.execute('CREATE TABLE recent (book_id TEXT, page_number INTEGER)');
    await db.execute('CREATE TABLE search_history (word TEXT, date TEXT, '
        'query_mode INTEGER)');
    await db.execute('CREATE TABLE dictionary_books (id INTEGER PRIMARY KEY, '
        'name TEXT, user_order INTEGER, user_choice INTEGER)');
  }

  test('bookmarks stay in their folders, and the rest comes too', () async {
    final old = await open();
    await schema(old);
    await old.insert('folder', {'id': 7, 'name': 'Suttas'});
    await old.insert('bookmark', {
      'id': 3, 'book_id': 'mula_sa_03', 'page_number': 55,
      'name': 'saṃyuttanikāya', 'selected_text': 'anattalakkhaṇasuttaṃ',
      'folder_id': 7, 'bmk_sort': 0,
    });
    await old.insert('recent', {'book_id': 'mula_di_01', 'page_number': 12});
    await old.insert('search_history',
        {'word': 'anatta', 'date': '2026-09-30', 'query_mode': 1});
    await old.insert('dictionary_books',
        {'id': 1, 'name': 'DPD', 'user_order': 5, 'user_choice': 0});

    final carried = await UserDataCarryOver.read(old);
    await old.close();

    // The newly shipped database: same tables, shipped dictionary defaults,
    // and a column the old one did not have.
    final fresh = await open();
    await schema(fresh, newColumn: true);
    await fresh.insert('dictionary_books',
        {'id': 1, 'name': 'DPD', 'user_order': 1, 'user_choice': 1});
    await carried.writeTo(fresh);

    final bookmark = (await fresh.query('bookmark')).single;
    expect(bookmark['folder_id'], 7);
    expect((await fresh.query('folder', where: 'id = 7')).single['name'],
        'Suttas');
    expect(bookmark['selected_text'], 'anattalakkhaṇasuttaṃ');
    expect((await fresh.query('recent')).single['page_number'], 12);
    expect((await fresh.query('search_history')).single['word'], 'anatta');
    final dpd = (await fresh.query('dictionary_books')).single;
    expect(dpd['user_order'], 5);
    expect(dpd['user_choice'], 0);
    await fresh.close();
  });

  test('a table missing on either side is skipped, not fatal', () async {
    final old = await open();
    await old.execute(
        'CREATE TABLE recent (book_id TEXT, page_number INTEGER)');
    await old.insert('recent', {'book_id': 'mula_di_01', 'page_number': 1});
    final carried = await UserDataCarryOver.read(old);
    await old.close();

    final fresh = await open();
    await carried.writeTo(fresh); // no tables at all
    await fresh.close();
  });
}
