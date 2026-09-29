import 'package:tipitaka_pali/business_logic/models/page_content.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/repositories/page_content_repo.dart';
import 'package:tipitaka_pali/utils/page_composer.dart';

/// Serves reader pages out of ePitaka's sentences instead of the `pages` table.
///
/// It implements the same interface the reader already uses, so nothing above
/// it changes: the reader still receives one HTML string per page, and script
/// conversion, word tap lookup, highlighting, the search anchor and TTS all
/// keep working on that string.
///
/// Where a page begins and ends comes from TPR, not from ePitaka. TPR is the
/// authority on pagination; ePitaka rounds a page to the nearest sentence, and
/// the inline anchor in the old pages sits a few words past the real break
/// because it marks where the page number is printed. The `page_break` table
/// carries TPR's own boundaries onto sentence coordinates, which is what this
/// reads.
///
/// Expects both databases attached to the open connection:
///
///   ATTACH DATABASE 'epitaka.db'      AS epi;
///   ATTACH DATABASE 'tpr_extension.db' AS ext;
class SentencePageContentRepository implements PageContentRepository {
  final DatabaseHelper databaseProvider;

  SentencePageContentRepository(this.databaseProvider);

  @override
  Future<PageContent?> getPageByBookAndPage(String bookID, int page) async {
    final db = await databaseProvider.database;
    final bounds = await db.rawQuery(
      'SELECT book_id, para_id, line_id, word_index FROM ext.page_break '
      'WHERE tpr_book = ? AND tpr_page = ? LIMIT 1',
      [bookID, page],
    );
    if (bounds.isEmpty) return null;

    final start = _Bound.from(bounds.first);

    // The next page's start ends this one. In a few books the boundary that
    // follows sits earlier in the text than this one, because it was placed
    // approximately where the two sources differ. Taking it literally would
    // ask for an empty range and show a blank page, so step forward to the
    // first boundary that genuinely comes after this one. A slightly long
    // page is a far better failure than a missing one.
    final nextRows = await db.rawQuery(
      'SELECT book_id, para_id, line_id, word_index FROM ext.page_break '
      'WHERE tpr_book = ? AND tpr_page > ? ORDER BY tpr_page LIMIT 8',
      [bookID, page],
    );
    _Bound? end;
    for (final row in nextRows) {
      final candidate = _Bound.from(row);
      if (candidate.isAfter(start)) {
        end = candidate;
        break;
      }
    }

    final sentences = await _sentencesBetween(db, start, end);
    if (sentences.isEmpty) return null;

    return PageContent(
      bookID: bookID,
      pageNumber: page,
      content: PageComposer.compose(
        sentences,
        // A page opening part-way through a sentence continues the paragraph
        // it interrupts, rather than indenting as if it were a new one.
        continuesFromPreviousPage: start.wordIndex > 0,
      ),
      paragraphNumber: '',
    );
  }

  Future<List<PageSentence>> _sentencesBetween(
      dynamic db, _Bound start, _Bound? end) async {
    final args = <Object?>[start.bookId, start.paraId, start.paraId, start.lineId];
    var range = '(s.para_id > ? OR (s.para_id = ? AND s.line_id >= ?))';
    if (end != null && end.bookId == start.bookId) {
      range += ' AND (s.para_id < ? OR (s.para_id = ? AND s.line_id <= ?))';
      args.addAll([end.paraId, end.paraId, end.lineId]);
    }

    // Most books come from ePitaka. The few it does not carry were converted
    // from TPR's own text and live in the extension, so fall through to them.
    var rows = await db.rawQuery(_sentenceQuery('epi.sentences', range), args);
    if (rows.isEmpty) {
      rows = await db.rawQuery(
          _sentenceQuery('ext.extra_sentence', range), args);
    }
    if (rows.isEmpty) return const [];

    final marks = await _anchorsFor(db, start, end);
    final translations = await _translationsFor(db, start, end);
    return _assemble(rows, start, end, marks, translations);
  }

  /// Turns rows into page sentences. Shared by the single-page path, which
  /// queries for them, and by [getPages], which slices them out of one bulk
  /// read of the whole book.
  List<PageSentence> _assemble(
    List<Map<String, Object?>> rows,
    _Bound start,
    _Bound? end,
    Map<String, List<PageAnchor>> marks,
    List<Map<String, String>> translations,
  ) {
    final sentences = <PageSentence>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final paraId = row['para_id'] as int;
      final lineId = row['line_id'] as int;
      var pali = _stripInlineMarkup(row['pali'] as String? ?? '');
      final anchors = marks[_key(paraId, lineId)] ?? const <PageAnchor>[];

      // Trim the sentences the page break falls inside, so a page that starts
      // or ends mid-sentence does exactly that.
      var dropped = 0;
      if (i == 0 && start.wordIndex > 0) {
        dropped = start.wordIndex;
        pali = _dropWords(pali, start.wordIndex);
      }
      if (end != null &&
          i == rows.length - 1 &&
          paraId == end.paraId &&
          lineId == end.lineId &&
          end.wordIndex > 0) {
        pali = _keepWords(pali, end.wordIndex - dropped);
      }
      if (pali.isEmpty) continue;

      sentences.add(PageSentence(
        paraId: paraId,
        lineId: lineId,
        pali: pali,
        paraNum: lineId == 1 ? row['vripara'] as String? : null,
        glue: _glue(row['glue_state'] as String?),
        translations: translations.isEmpty
            ? const []
            : [
                for (final byLanguage in translations)
                  byLanguage[_key(paraId, lineId)] ?? ''
              ],
        anchors: dropped == 0
            ? anchors
            : anchors
                .where((a) => a.wordIndex >= dropped)
                .map((a) => PageAnchor(
                      edition: a.edition,
                      volume: a.volume,
                      page: a.page,
                      wordIndex: a.wordIndex - dropped,
                    ))
                .toList(),
      ));
    }
    return sentences;
  }

  static String _sentenceQuery(String table, String range) =>
      'SELECT s.para_id, s.line_id, s.pali, s.vripara, e.glue_state '
      'FROM $table s '
      'LEFT JOIN ext.sentence_ext e '
      '  ON e.book_id = s.book_id AND e.para_id = s.para_id '
      '  AND e.line_id = s.line_id '
      'WHERE s.book_id = ? AND $range '
      'ORDER BY s.para_id, s.line_id';

  /// Translations for this page, one map per active language, in display
  /// order.
  ///
  /// A language is queried only if it is both installed and switched on. A
  /// sentence with no translation in a given language yields an empty string,
  /// which the composer skips, so a gap in one language does not shift the
  /// others out of order.
  Future<List<Map<String, String>>> _translationsFor(
      dynamic db, _Bound start, _Bound? end) async {
    final installed = DatabaseHelper.installedLanguages;
    if (installed.isEmpty) return const [];
    // Switched off means switched off. An empty list used to mean "show
    // everything installed", which was right while there was no way to turn
    // one off and wrong as soon as there was.
    final codes =
        Prefs.activeLanguages.where(installed.contains).toList();
    if (codes.isEmpty) return const [];

    final args = <Object?>[start.bookId, start.paraId, start.paraId, start.lineId];
    var range = '(para_id > ? OR (para_id = ? AND line_id >= ?))';
    if (end != null && end.bookId == start.bookId) {
      range += ' AND (para_id < ? OR (para_id = ? AND line_id <= ?))';
      args.addAll([end.paraId, end.paraId, end.lineId]);
    }

    final out = <Map<String, String>>[];
    for (final code in codes) {
      try {
        final rows = await db.rawQuery(
          'SELECT para_id, line_id, translation FROM lang_$code.sentences '
          'WHERE book_id = ? AND $range ORDER BY para_id, line_id',
          args,
        );
        final byKey = <String, String>{};
        for (final row in rows) {
          final text = (row['translation'] as String?)?.trim() ?? '';
          if (text.isEmpty) continue;
          byKey[_key(row['para_id'] as int, row['line_id'] as int)] = text;
        }
        out.add(byKey);
      } catch (_) {
        // A language that will not answer costs that language, not the page.
        out.add(const {});
      }
    }
    return out;
  }

  /// Page-number positions falling inside this page, by sentence.
  ///
  /// Myanmar is left out on purpose: it is the pagination itself, shown as the
  /// page number, not as a marker inside the text.
  Future<Map<String, List<PageAnchor>>> _anchorsFor(
      dynamic db, _Bound start, _Bound? end) async {
    final args = <Object?>[start.bookId, start.paraId, start.paraId, start.lineId];
    var range = '(para_id > ? OR (para_id = ? AND line_id >= ?))';
    if (end != null && end.bookId == start.bookId) {
      range += ' AND (para_id < ? OR (para_id = ? AND line_id <= ?))';
      args.addAll([end.paraId, end.paraId, end.lineId]);
    }

    final rows = await db.rawQuery(
      'SELECT para_id, line_id, edition, vol, page, word_index '
      'FROM ext.page_mark '
      "WHERE book_id = ? AND edition <> 'M' AND $range "
      'ORDER BY para_id, line_id, word_index',
      args,
    );

    final out = <String, List<PageAnchor>>{};
    for (final row in rows) {
      final key = _key(row['para_id'] as int, row['line_id'] as int);
      out.putIfAbsent(key, () => []).add(PageAnchor(
            edition: row['edition'] as String,
            volume: (row['vol'] as int?) ?? 0,
            page: (row['page'] as int?) ?? 0,
            wordIndex: row['word_index'] as int,
          ));
    }
    return out;
  }

  @override
  /// Every page of a book, which is what the reader asks for when it opens
  /// one.
  ///
  /// Read in bulk. Asking for each page in turn meant five queries and a
  /// composition per page, so a book of four hundred pages cost two thousand
  /// queries before a word appeared — the old `pages` table answered the same
  /// question with one. Everything the book needs is now read in a handful of
  /// queries and the pages are cut out of it in memory.
  @override
  Future<List<PageContent>> getPages(String bookID) async {
    final db = await databaseProvider.database;

    final breaks = await db.rawQuery(
      'SELECT book_id, para_id, line_id, word_index, tpr_page '
      'FROM ext.page_break WHERE tpr_book = ? ORDER BY tpr_page',
      [bookID],
    );
    if (breaks.isEmpty) return const [];

    // A TPR book can span more than one ePitaka book, so read by the books
    // the boundaries actually name.
    final epiBooks = <String>{
      for (final row in breaks) row['book_id'] as String
    }.toList();

    final sentences = <String, List<Map<String, Object?>>>{};
    for (final book in epiBooks) {
      var rows = await db.rawQuery(
        'SELECT s.para_id, s.line_id, s.pali, s.vripara, e.glue_state '
        'FROM epi.sentences s '
        'LEFT JOIN ext.sentence_ext e '
        '  ON e.book_id = s.book_id AND e.para_id = s.para_id '
        '  AND e.line_id = s.line_id '
        'WHERE s.book_id = ? ORDER BY s.para_id, s.line_id',
        [book],
      );
      if (rows.isEmpty) {
        rows = await db.rawQuery(
          'SELECT s.para_id, s.line_id, s.pali, s.vripara, e.glue_state '
          'FROM ext.extra_sentence s '
          'LEFT JOIN ext.sentence_ext e '
          '  ON e.book_id = s.book_id AND e.para_id = s.para_id '
          '  AND e.line_id = s.line_id '
          'WHERE s.book_id = ? ORDER BY s.para_id, s.line_id',
          [book],
        );
      }
      sentences[book] = rows;
    }

    final marks = <String, Map<String, List<PageAnchor>>>{};
    for (final book in epiBooks) {
      marks[book] = await _allAnchorsFor(db, book);
    }
    final translations = <String, List<Map<String, String>>>{};
    for (final book in epiBooks) {
      translations[book] = await _allTranslationsFor(db, book);
    }

    final out = <PageContent>[];
    for (var i = 0; i < breaks.length; i++) {
      final start = _Bound.from(breaks[i]);
      _Bound? end;
      for (var j = i + 1; j < breaks.length && j <= i + 8; j++) {
        final candidate = _Bound.from(breaks[j]);
        if (candidate.isAfter(start)) {
          end = candidate;
          break;
        }
      }

      final all = sentences[start.bookId] ?? const [];
      final slice = <Map<String, Object?>>[];
      for (final row in all) {
        final para = row['para_id'] as int;
        final line = row['line_id'] as int;
        if (para < start.paraId ||
            (para == start.paraId && line < start.lineId)) {
          continue;
        }
        if (end != null && end.bookId == start.bookId) {
          if (para > end.paraId ||
              (para == end.paraId && line > end.lineId)) {
            break;
          }
        }
        slice.add(row);
      }
      if (slice.isEmpty) continue;

      final built = _assemble(slice, start, end,
          marks[start.bookId] ?? const {}, translations[start.bookId] ?? const []);
      if (built.isEmpty) continue;

      out.add(PageContent(
        bookID: bookID,
        pageNumber: breaks[i]['tpr_page'] as int,
        content: PageComposer.compose(
          built,
          continuesFromPreviousPage: start.wordIndex > 0,
        ),
        paragraphNumber: '',
      ));
    }
    return out;
  }

  /// Every page-number position in a book, by sentence.
  Future<Map<String, List<PageAnchor>>> _allAnchorsFor(
      dynamic db, String book) async {
    final rows = await db.rawQuery(
      "SELECT para_id, line_id, edition, vol, page, word_index "
      "FROM ext.page_mark WHERE book_id = ? AND edition <> 'M' "
      "ORDER BY para_id, line_id, word_index",
      [book],
    );
    final out = <String, List<PageAnchor>>{};
    for (final row in rows) {
      out
          .putIfAbsent(
              _key(row['para_id'] as int, row['line_id'] as int),
              () => <PageAnchor>[])
          .add(PageAnchor(
            edition: row['edition'] as String,
            volume: (row['vol'] as int?) ?? 0,
            page: (row['page'] as int?) ?? 0,
            wordIndex: row['word_index'] as int,
          ));
    }
    return out;
  }

  /// Every translation in a book, one map per shown language.
  Future<List<Map<String, String>>> _allTranslationsFor(
      dynamic db, String book) async {
    final installed = DatabaseHelper.installedLanguages;
    if (installed.isEmpty) return const [];
    final codes = Prefs.activeLanguages.where(installed.contains).toList();
    if (codes.isEmpty) return const [];

    final out = <Map<String, String>>[];
    for (final code in codes) {
      try {
        final rows = await db.rawQuery(
          'SELECT para_id, line_id, translation FROM lang_$code.sentences '
          'WHERE book_id = ? ORDER BY para_id, line_id',
          [book],
        );
        final byKey = <String, String>{};
        for (final row in rows) {
          final text = (row['translation'] as String?)?.trim() ?? '';
          if (text.isEmpty) continue;
          byKey[_key(row['para_id'] as int, row['line_id'] as int)] = text;
        }
        out.add(byKey);
      } catch (_) {
        out.add(const {});
      }
    }
    return out;
  }

  @override
  Future<PageContent> getPage(int id) {
    // Pages have no standalone id in the sentence data; they are addressed by
    // book and page number.
    throw UnsupportedError(
        'getPage(id) has no meaning for sentence-based pages; '
        'use getPageByBookAndPage');
  }

  static String _key(int paraId, int lineId) => '$paraId.$lineId';

  static GlueState _glue(String? state) {
    switch (state) {
      case 'continue':
        return GlueState.continues;
      case 'verse':
        return GlueState.verse;
      default:
        return GlueState.paragraph;
    }
  }

  /// ePitaka keeps `<b>`, `<sup>` and `<i>` inside the Pali itself, on about a
  /// quarter of its sentences. They are dropped here so that a word offset
  /// means the same thing as it did when it was measured.
  static String _stripInlineMarkup(String pali) =>
      pali.replaceAll(RegExp(r'<[^>]*>'), '').trim();

  static String _dropWords(String text, int count) {
    final words = text.split(' ');
    if (count >= words.length) return '';
    return words.sublist(count).join(' ');
  }

  static String _keepWords(String text, int count) {
    if (count <= 0) return '';
    final words = text.split(' ');
    if (count >= words.length) return text;
    return words.sublist(0, count).join(' ');
  }
}

class _Bound {
  final String bookId;
  final int paraId;
  final int lineId;
  final int wordIndex;

  const _Bound(this.bookId, this.paraId, this.lineId, this.wordIndex);

  /// Whether this boundary sits later in the text than [other].
  bool isAfter(_Bound other) {
    if (bookId != other.bookId) return true; // a later part of the book
    if (paraId != other.paraId) return paraId > other.paraId;
    if (lineId != other.lineId) return lineId > other.lineId;
    return wordIndex > other.wordIndex;
  }

  factory _Bound.from(Map<String, Object?> row) => _Bound(
        row['book_id'] as String,
        row['para_id'] as int,
        row['line_id'] as int,
        row['word_index'] as int,
      );
}
