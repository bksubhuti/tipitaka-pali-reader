import 'package:tipitaka_pali/business_logic/models/toc.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/repositories/toc_repo.dart';

/// The table of contents, taken from ePitaka's headings.
///
/// The old contents live in a `tocs` table keyed by page, built when the page
/// database was. ePitaka carries the same structure as `headings` keyed by
/// paragraph, with a level and a parent, which is where it belongs: a heading
/// marks a place in the text, not a place on a printed page.
///
/// The reader still opens by page, so each heading is resolved to the page its
/// paragraph falls on, using the same boundaries the reader paginates by.
class SentenceTocRepository implements TocRepository {
  final DatabaseHelper databaseProvider;

  SentenceTocRepository(this.databaseProvider);

  /// ePitaka nests headings more finely than TPR's four kinds. Levels are
  /// folded onto the names the contents dialog already knows how to indent.
  ///
  /// Level 10 is not a heading at all: it is the paragraph number, of which
  /// there are over a hundred thousand. Including those would bury the
  /// contents in numbers.
  static String _typeForLevel(int level) {
    if (level <= 2) return 'chapter';
    if (level == 3) return 'title';
    if (level <= 5) return 'subhead';
    return 'subsubhead';
  }

  @override
  Future<List<Toc>> getTocs(String bookID) async {
    final db = await databaseProvider.database;
    final rows = await db.rawQuery('''
      SELECT h.title, h.level, h.book_id, h.para_id,
        (SELECT b.tpr_page FROM ext.page_break b
          WHERE b.tpr_book = ? AND b.book_id = h.book_id
            AND b.para_id <= h.para_id
          ORDER BY b.para_id DESC, b.line_id DESC LIMIT 1) AS page
      FROM epi.headings h
      WHERE h.book_id IN (
              SELECT DISTINCT book_id FROM ext.page_break WHERE tpr_book = ?)
        AND h.level < 10
        AND h.title IS NOT NULL AND h.title <> ''
      ORDER BY h.book_id, h.para_id
    ''', [bookID, bookID]);

    // Where a later volume of the same ePitaka book begins: another TPR book
    // lying wholly after this one's last page. Its headings are its own, and
    // without this they were listed here too, all on this book's last page.
    final ends = <String, int>{};
    for (final row in await db.rawQuery('''
      SELECT b.book_id, min(b.para_id) AS para
      FROM ext.page_break b
      JOIN (SELECT book_id, max(para_id) AS last FROM ext.page_break
            WHERE tpr_book = ? GROUP BY book_id) mine
        ON mine.book_id = b.book_id
      WHERE b.tpr_book <> ?
      GROUP BY b.book_id, b.tpr_book
      HAVING min(b.para_id) > max(mine.last)
    ''', [bookID, bookID])) {
      final book = row['book_id'] as String;
      final para = row['para'] as int;
      if (para < (ends[book] ?? para + 1)) ends[book] = para;
    }

    final tocs = <Toc>[];
    for (final row in rows) {
      final page = row['page'] as int?;
      // A heading whose paragraph falls outside this book's pages belongs to
      // another volume sharing the same ePitaka book.
      if (page == null) continue;
      final end = ends[row['book_id']];
      if (end != null && (row['para_id'] as int) >= end) continue;
      tocs.add(Toc(
        row['title'] as String,
        _typeForLevel(row['level'] as int? ?? 4),
        page,
      ));
    }
    return tocs;
  }
}
