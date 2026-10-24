import 'package:flutter/foundation.dart';

import '../../business_logic/models/list_item.dart';
import '../database/database_helper.dart';

/// The books inside TPR volumes that hold more than one.
///
/// The root text of the Aṅguttara has a book for each of its eleven
/// nipātas, but the commentary and ṭīkā put them in four volumes. ePitaka
/// keeps each nipāta a book of its own, and the page breaks say where each
/// begins, so the library can list them as books while the volume, its ids,
/// page numbers and bookmarks stay as they are. Some twenty volumes are
/// like this: the Aṅguttara's, the Abhidhamma commentaries and ṭīkās,
/// several Vinaya ṭīkās and a few in Añña.
class VolumeParts {
  static Map<String, List<(String, int)>>? _parts;

  /// Each such volume's books, by TPR book, as name and first page, in page
  /// order. Empty without the sentence data, which is what names them; not
  /// remembered then, as the database may simply not be ready yet.
  static Future<Map<String, List<(String, int)>>> load() async {
    if (_parts case final parts?) return parts;
    try {
      final db = await DatabaseHelper().database;
      final rows = await db.rawQuery('''
        SELECT b.tpr_book, MIN(b.tpr_page) AS page, e.book_name
        FROM ext.page_break b
        JOIN epi.books e ON e.book_id = b.book_id
        WHERE b.tpr_book IN (SELECT tpr_book FROM ext.page_break
                             GROUP BY tpr_book
                             HAVING COUNT(DISTINCT book_id) > 1)
        GROUP BY b.tpr_book, b.book_id
        ORDER BY b.tpr_book, page''');
      final parts = <String, List<(String, int)>>{};
      for (final row in rows) {
        final name = row['book_name'] as String? ?? '';
        if (name.isEmpty) continue;
        // Lower case, as the books' own names are.
        parts.putIfAbsent(row['tpr_book'] as String, () => []).add(
            (name[0].toLowerCase() + name.substring(1), row['page'] as int));
      }
      if (parts.isNotEmpty) _parts = parts;
      return parts;
    } catch (e) {
      debugPrint('volume parts: $e');
      return const {};
    }
  }

  /// [items] with each volume of several books replaced by those books, each
  /// covering its pages of the volume.
  static Future<List<BookItem>> split(List<BookItem> items) async {
    final parts = await load();
    return [
      for (final item in items)
        if (parts[item.book.id] case final ps?)
          for (var i = 0; i < ps.length; i++)
            BookItem(item.book,
                part: ps[i].$1,
                fromPage: ps[i].$2,
                toPage: i + 1 < ps.length ? ps[i + 1].$2 - 1 : null)
        else
          item,
    ];
  }
}
