import 'package:tipitaka_pali/business_logic/models/sutta.dart';
import '../database/database_helper.dart';
import '../prefs.dart';

abstract class SuttaRepository {
  Future<List<Sutta>> getAll();
  Future<List<Sutta>> getSuttas(String filterWord);
}

class SuttaRepositoryDatabase implements SuttaRepository {
  final DatabaseHelper databaseProvider;

  // Regex to detect if the query is a shortcut (e.g., "dn 1", "mn12", "sn 56.11")
  final reShortcut = RegExp(r'^[a-z]+ ?\d+', caseSensitive: false);

  SuttaRepositoryDatabase(this.databaseProvider);

  @override
  Future<List<Sutta>> getAll() async {
    final db = await databaseProvider.database;

    // Selecting all necessary columns to match the Sutta model.
    // We alias 'book_id' as 'book_name' since we are not joining the books table.
    var results = await db.rawQuery('''
      SELECT 
        sutta_name as name, 
        book_id, 
        book_id as book_name, 
        start_page,
        end_page,
        sutta_shortcut as shortcut
      FROM sutta_page_shortcut
    ''');

    return results.map((e) => Sutta.fromMap(e)).toList();
  }

  @override
  Future<List<Sutta>> getSuttas(String filterWord) async {
    final db = await databaseProvider.database;
    String cleanInput = filterWord.trim();

    // 1. SHORTCUT SEARCH (e.g., "dn 1", "mn 10")
    if (reShortcut.hasMatch(cleanInput)) {
      // Remove spaces to match the DB format (e.g., "dn 1" becomes "dn1")
      String lookup = cleanInput.toLowerCase().replaceAll(' ', '');

      var results = await db.rawQuery('''
        SELECT 
          sutta_name as name, 
          book_id, 
          book_id as book_name, 
          start_page, 
          end_page,
          sutta_shortcut as shortcut
        FROM sutta_page_shortcut
        WHERE sutta_shortcut LIKE '$lookup%'
      ''');

      return results.map((e) => Sutta.fromMap(e)).toList();
    }

    // 2. TEXT SEARCH
    else {
      if (Prefs.isFuzzy) {
        // FUZZY: Normalize input and search the 'simple' column
        String simpleFilteredWord = _normalize(cleanInput);

        var fuzzyResults = await db.rawQuery('''
          SELECT 
            sutta_name as name, 
            book_id, 
            book_id as book_name, 
            start_page,
            end_page,
            sutta_shortcut as shortcut
          FROM sutta_page_shortcut
          WHERE simple LIKE '%$simpleFilteredWord%'
        ''');

        return fuzzyResults.map((e) => Sutta.fromMap(e)).toList();
      } else {
        // EXACT: Search the standard 'sutta_name' column
        var results = await db.rawQuery('''
          SELECT 
            sutta_name as name, 
            book_id, 
            book_id as book_name, 
            start_page,
            end_page,
            sutta_shortcut as shortcut
          FROM sutta_page_shortcut
          WHERE sutta_name LIKE '%$cleanInput%'
        ''');

        return results.map((e) => Sutta.fromMap(e)).toList();
      }
    }
  }

  // Helper to remove diacritics for normalizing the input
  String _normalize(String input) {
    return input.replaceAllMapped(
      RegExp('[ṭḍṃāūīḷñṅ]'),
      (match) => {
        'ṭ': 't',
        'ḍ': 'd',
        'ṃ': 'm',
        'ā': 'a',
        'ū': 'u',
        'ī': 'i',
        'ḷ': 'l',
        'ñ': 'n',
        'ṅ': 'n'
      }[match.group(0)]!,
    );
  }
}
