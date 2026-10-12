import 'package:tipitaka_pali/services/database/database_helper.dart';

/// The headings a place in the text sits under, from the book down: for a
/// sutta in the Dīgha, "(DN) Sīlakkhandhavaggapāḷi", "7. Jāliyasuttaṃ",
/// "Dvepabbajitavatthu". Taken from ePitaka's headings, where each heading
/// marks the paragraph it opens and has a level, 1 for the book.
class HeadingTrail {
  const HeadingTrail(this.titles, this.suttaCentralId);

  /// The headings, the book first.
  final List<String> titles;

  /// The SuttaCentral reference of the nearest heading that has one, as
  /// written there: "dn7", "sn6.14".
  final String? suttaCentralId;

  /// The trail from [rows] of headings (`level`, `title`, `sc_id`), the
  /// nearest first: back from there, the nearest heading at each level
  /// above the last one taken, until the book's own. Null with none.
  static HeadingTrail? fromRows(Iterable<Map<String, Object?>> rows) {
    final titles = <String>[];
    String? scId;
    var above = 1 << 30;
    for (final row in rows) {
      final level = row['level'] as int;
      if (level >= above) continue;
      above = level;
      // "(MN)Majjhimapaṇṇāsapāḷi" is written without its space.
      titles.insert(
          0,
          (row['title'] as String).replaceFirstMapped(
              RegExp(r'^(\([A-Z]+\))(?=\S)'), (m) => '${m[1]} '));
      final id = row['sc_id'] as String?;
      if (scId == null && id != null && id.isNotEmpty) scId = id;
      if (level <= 1) break;
    }
    return titles.isEmpty ? null : HeadingTrail(titles, scId);
  }

  /// [suttaCentralId] as it is cited: "DN 7", "SN 6.14", "Dhp 1". Null
  /// for references not cited this way, such as the Vinaya's
  /// "pli-tv-bu-vb-pj3".
  String? get citation {
    final m =
        RegExp(r'^([a-z]+)(\d[\d.\-]*)$').firstMatch(suttaCentralId ?? '');
    if (m == null) return null;
    final work = m[1]!;
    final name = const {'dn', 'mn', 'sn', 'an'}.contains(work)
        ? work.toUpperCase()
        : work[0].toUpperCase() + work.substring(1);
    return '$name ${m[2]}';
  }
}

class HeadingTrailRepository {
  HeadingTrailRepository(this.databaseProvider);
  final DatabaseHelper databaseProvider;

  /// The headings over paragraph [paraId] of TPR's [tprBook], on [page].
  /// The page says which of ePitaka's books it is, as one TPR book can hold
  /// more than one of them. Null for a book not in the sentence data.
  Future<HeadingTrail?> of(String tprBook, int page, int paraId) async {
    final db = await databaseProvider.database;
    final book = await db.rawQuery(
        'SELECT book_id FROM ext.page_break WHERE tpr_book = ? '
        'AND tpr_page <= ? ORDER BY tpr_page DESC, para_id DESC LIMIT 1',
        [tprBook, page]);
    if (book.isEmpty) return null;
    final rows = await db.rawQuery(
        'SELECT level, title, sc_id FROM epi.headings '
        'WHERE book_id = ? AND para_id <= ? AND level < 10 '
        "AND title IS NOT NULL AND title <> '' "
        'ORDER BY para_id DESC',
        [book.first['book_id'], paraId]);

    return HeadingTrail.fromRows(rows);
  }
}
