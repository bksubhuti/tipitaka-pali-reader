import 'package:tipitaka_pali/business_logic/models/paragraph_mapping.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/repositories/paragraph_mapping_repo.dart';

/// The links between root text, commentary and sub-commentary, taken from
/// ePitaka's `book_links`.
///
/// The old mapping is page to page and approximate: it says this page has
/// something to do with that page. ePitaka records the link at the word, half
/// a million of them, so a jump can land on the sentence that is actually
/// being commented on rather than somewhere on the right page.
///
/// The reader still opens by page, so the sentence is resolved back to one.
/// The gain is accuracy in finding the link, not a change in what happens
/// afterwards.
class SentenceParagraphMappingRepository implements ParagraphMappingRepository {
  final DatabaseHelper databaseProvider;

  SentenceParagraphMappingRepository(this.databaseProvider);

  @override
  Future<List<ParagraphMapping>> getParagraphMappings(
          String bookID, int pageNumber) =>
      _links(bookID, pageNumber, forward: true);

  @override
  Future<List<ParagraphMapping>> getBackWardParagraphMappings(
          String bookID, int pageNumber) =>
      _links(bookID, pageNumber, forward: false);

  /// Links leaving this page, or arriving at it.
  ///
  /// [forward] follows root to commentary, the direction the commentary
  /// button asks for. Backwards follows commentary to root.
  Future<List<ParagraphMapping>> _links(
    String bookID,
    int pageNumber, {
    required bool forward,
  }) async {
    final db = await databaseProvider.database;

    // Where this page begins and ends, in sentence terms.
    final bounds = await db.rawQuery(
      'SELECT book_id, para_id, line_id FROM ext.page_break '
      'WHERE tpr_book = ? AND tpr_page >= ? ORDER BY tpr_page LIMIT 2',
      [bookID, pageNumber],
    );
    if (bounds.isEmpty) return const [];
    final epiBook = bounds.first['book_id'] as String;
    final fromPara = bounds.first['para_id'] as int;
    final toPara = bounds.length > 1 && bounds[1]['book_id'] == epiBook
        ? bounds[1]['para_id'] as int
        : null;

    final here = forward ? 'src' : 'dst';
    final there = forward ? 'dst' : 'src';

    final args = <Object?>[epiBook, fromPara];
    var range = 'l.${here}_para >= ?';
    if (toPara != null) {
      range += ' AND l.${here}_para <= ?';
      args.add(toPara);
    }

    // The page a linked paragraph sits on, in the reader's own numbering.
    final rows = await db.rawQuery('''
      SELECT DISTINCT l.${there}_book AS book, l.${there}_para AS para,
        (SELECT b.tpr_book FROM ext.page_break b
          WHERE b.book_id = l.${there}_book AND b.para_id <= l.${there}_para
          ORDER BY b.para_id DESC LIMIT 1) AS tpr_book,
        (SELECT b.tpr_page FROM ext.page_break b
          WHERE b.book_id = l.${there}_book AND b.para_id <= l.${there}_para
          ORDER BY b.para_id DESC LIMIT 1) AS tpr_page,
        (SELECT s.vripara FROM epi.sentences s
          WHERE s.book_id = l.${there}_book AND s.para_id <= l.${there}_para
            AND s.vripara IS NOT NULL AND s.vripara <> ''
          ORDER BY s.para_id DESC LIMIT 1) AS printed
      FROM epi.book_links l
      WHERE l.${here}_book = ? AND $range
      ORDER BY l.${there}_book, l.${there}_para
      LIMIT 200
    ''', args);

    final mappings = <ParagraphMapping>[];
    final seen = <String>{};
    for (final row in rows) {
      final targetBook = row['tpr_book'] as String?;
      final targetPage = row['tpr_page'] as int?;
      // A link into text TPR has no page for cannot be opened.
      if (targetBook == null || targetPage == null) continue;
      if (!seen.add('$targetBook.$targetPage')) continue;

      final names = await db.rawQuery(
          'SELECT name FROM books WHERE id = ? LIMIT 1', [targetBook]);
      if (names.isEmpty) continue;

      mappings.add(ParagraphMapping(
        paragraph: row['para'] as int? ?? 0,
        baseBookID: bookID,
        basePageNumber: pageNumber,
        expBookID: targetBook,
        expPageNumber: targetPage,
        bookName: names.first['name'] as String,
        // The number printed at the head of the paragraph, or of the one it
        // continues. The para_id is a running count, 1209 where the book
        // says 421.
        printedNumber: row['printed']?.toString(),
      ));
    }
    return mappings;
  }
}
