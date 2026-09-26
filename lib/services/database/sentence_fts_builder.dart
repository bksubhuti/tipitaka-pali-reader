import 'package:sqflite/sqflite.dart';

/// Builds the search index from ePitaka's sentences, on the device.
///
/// Nothing is shipped: the index is derived from data already installed, the
/// same way TPR builds `fts_pages` today. That keeps the download small and
/// means the index always matches whatever sentence data is actually present.
///
/// What gets indexed is the point of the exercise. Phrase search works today
/// because the indexed unit is larger than a sentence: a whole printed page is
/// one string, so a phrase running across a sentence boundary still matches.
/// Indexing single sentences would lose that. Indexing single paragraphs would
/// keep it but shorten the reach of distance search, a paragraph running about
/// forty words against a page's two hundred.
///
/// So a unit is a run of whole paragraphs of roughly page size, and
/// consecutive units overlap by one paragraph. Unit boundaries fall only
/// between paragraphs, never inside a sentence, and the overlap means nothing
/// falls between two units. A phrase broken across a printed page break, which
/// today is findable only if it happens to recur elsewhere, is found.
///
/// Pali and translations are indexed separately and deliberately so. Mixing
/// translation text into the Pali index corrupts word distance and spoils the
/// AI search samples. They are searched together by querying both, not by
/// putting them in one table.
class SentenceFtsBuilder {
  SentenceFtsBuilder._();

  /// Roughly a printed page, which is the reach distance search expects.
  static const targetWords = 200;

  /// Paragraphs of overlap between consecutive units.
  static const overlapParagraphs = 1;

  static const _createPali = '''
CREATE VIRTUAL TABLE IF NOT EXISTS fts_unit USING FTS5(
  id UNINDEXED,
  bookid UNINDEXED,
  page UNINDEXED,
  content,
  plain UNINDEXED,
  page_map UNINDEXED,
  paranum UNINDEXED,
  sutta_name,
  tokenize = 'porter'
);''';

  static const _createTranslation = '''
CREATE VIRTUAL TABLE IF NOT EXISTS fts_translation_unit USING FTS5(
  id UNINDEXED,
  bookid UNINDEXED,
  page UNINDEXED,
  content,
  plain UNINDEXED,
  page_map UNINDEXED,
  paranum UNINDEXED,
  sutta_name,
  lang UNINDEXED,
  tokenize = 'porter'
);''';

  /// True when the index already exists and holds rows.
  static Future<bool> isBuilt(Database db) async {
    final tables = await db.rawQuery(
        "SELECT count(*) AS n FROM sqlite_master "
        "WHERE type='table' AND name='fts_unit'");
    if ((tables.first['n'] as int) == 0) return false;
    final rows = await db.rawQuery('SELECT count(*) AS n FROM fts_unit');
    return (rows.first['n'] as int) > 0;
  }

  /// The languages the translation index was built from, in order.
  static Future<List<String>> indexedLanguages(Database db) async {
    try {
      final rows = await db.rawQuery(
          'SELECT DISTINCT lang FROM fts_translation_unit ORDER BY lang');
      return rows.map((r) => r['lang'] as String).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Builds the index. Existing tables are replaced, so a rerun is safe.
  ///
  /// [languages] are the installed language codes; each gets translation units
  /// aligned to the Pali ones, so a hit in either can be shown against the
  /// same passage.
  ///
  /// [onProgress] is called with a message suitable for showing to the user.
  static Future<int> build(
    Database db, {
    List<String> languages = const [],
    void Function(String message)? onProgress,
  }) async {
    await db.execute('DROP TABLE IF EXISTS fts_unit;');
    await db.execute('DROP TABLE IF EXISTS fts_translation_unit;');
    await db.execute(_createPali);
    await db.execute(_createTranslation);

    // Where each page begins, so a result can open in the reader. The reader
    // is addressed by book and page, and that numbering is unchanged by the
    // migration, so every unit records the page it starts on.
    final breaks = await db.rawQuery(
      'SELECT book_id, para_id, tpr_book, tpr_page FROM ext.page_break '
      'ORDER BY book_id, para_id, line_id',
    );
    final pageStarts = <String, List<_PageStart>>{};
    for (final row in breaks) {
      pageStarts
          .putIfAbsent(row['book_id'] as String, () => <_PageStart>[])
          .add(_PageStart(
            row['para_id'] as int,
            row['tpr_book'] as String,
            row['tpr_page'] as int,
          ));
    }

    final books = await db.rawQuery(
        'SELECT DISTINCT book_id FROM epi.sentences ORDER BY book_id');

    var unitId = 0;
    var indexed = 0;
    var done = 0;
    for (final bookRow in books) {
      final book = bookRow['book_id'] as String;
      final starts = pageStarts[book];
      done++;
      if (starts == null || starts.isEmpty) {
        // ePitaka carries books TPR has no pages for. A result in one could
        // not be opened, so it is left out rather than returned as a dead end.
        continue;
      }

      final sentences = await db.rawQuery(
        'SELECT para_id, pali FROM epi.sentences WHERE book_id = ? '
        'ORDER BY para_id, line_id',
        [book],
      );
      if (sentences.isEmpty) continue;

      // group sentences into paragraphs, keeping paragraph order
      final paragraphs = <int, StringBuffer>{};
      final order = <int>[];
      for (final row in sentences) {
        final para = row['para_id'] as int;
        final text = _clean(row['pali'] as String? ?? '');
        if (text.isEmpty) continue;
        final buffer = paragraphs.putIfAbsent(para, () {
          order.add(para);
          return StringBuffer();
        });
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(text);
      }
      if (order.isEmpty) continue;

      // Translations for this book, per language, grouped the same way. Built
      // from the same paragraph boundaries as the Pali rather than from the
      // translation's own lengths, so a unit means the same passage in every
      // language and a hit in one can be shown against the other.
      final byLanguage = <String, Map<int, String>>{};
      for (final code in languages) {
        final map = <int, String>{};
        try {
          final rows = await db.rawQuery(
            'SELECT para_id, translation FROM lang_$code.sentences '
            'WHERE book_id = ? ORDER BY para_id, line_id',
            [book],
          );
          for (final row in rows) {
            final text = _clean(row['translation'] as String? ?? '');
            if (text.isEmpty) continue;
            final para = row['para_id'] as int;
            map[para] = map.containsKey(para) ? '${map[para]} $text' : text;
          }
        } catch (_) {
          // A language that will not answer is left out of the index.
        }
        if (map.isNotEmpty) byLanguage[code] = map;
      }

      // A committed batch is not emptied, so it must be replaced after every
      // commit. Reusing it re-applies everything already written and quietly
      // multiplies the index.
      var batch = db.batch();
      var pending = 0;
      var i = 0;
      while (i < order.length) {
        var words = 0;
        var j = i;
        final content = StringBuffer();
        while (j < order.length && (j == i || words < targetWords)) {
          final text = paragraphs[order[j]]!.toString();
          if (content.isNotEmpty) content.write(' ');
          content.write(text);
          words += _countWords(text);
          j++;
        }

        // Where each page begins inside this unit, as "wordOffset:page".
        // A unit is about a page long and overlaps its neighbour, so a match
        // often falls past the page the unit started on. Without this the
        // result opens on the wrong page and the reader cannot find the
        // phrase to highlight.
        final page = _pageFor(starts, order[i]);
        final map = StringBuffer('0:${page.tprPage}');
        var offset = 0;
        var lastPage = page.tprPage;
        for (var k = i; k < j; k++) {
          final paraPage = _pageFor(starts, order[k]);
          if (paraPage.tprPage != lastPage) {
            map.write(',$offset:${paraPage.tprPage}');
            lastPage = paraPage.tprPage;
          }
          offset += _countWords(paragraphs[order[k]]!.toString());
        }

        final text = content.toString();
        batch.insert('fts_unit', {
          'id': ++unitId,
          'bookid': page.tprBook,
          'page': page.tprPage,
          'content': text,
          'plain': plainForm(text),
          'page_map': map.toString(),
          'paranum': '${order[i]}-${order[j - 1]}',
          'sutta_name': '',
        });
        for (final entry in byLanguage.entries) {
          final translated = StringBuffer();
          for (var k = i; k < j; k++) {
            final text = entry.value[order[k]];
            if (text == null || text.isEmpty) continue;
            if (translated.isNotEmpty) translated.write(' ');
            translated.write(text);
          }
          if (translated.isEmpty) continue;
          final translatedText = translated.toString();
          batch.insert('fts_translation_unit', {
            'id': unitId,
            'bookid': page.tprBook,
            'page': page.tprPage,
            'content': translatedText,
            'plain': plainForm(translatedText),
            'page_map': map.toString(),
            'paranum': '${order[i]}-${order[j - 1]}',
            'sutta_name': '',
            'lang': entry.key,
          });
          pending++;
        }

        indexed++;
        if (++pending >= 300) {
          await batch.commit(noResult: true);
          batch = db.batch();
          pending = 0;
        }

        if (j >= order.length) break;
        // step back one paragraph so nothing falls between two units
        i = (i + 1) > (j - overlapParagraphs) ? i + 1 : j - overlapParagraphs;
      }
      if (pending > 0) await batch.commit(noResult: true);

      if (onProgress != null && done % 10 == 0) {
        onProgress('Building search index: '
            '${(done / books.length * 100).round()}%');
      }
    }

    onProgress?.call('Search index built');
    return indexed;
  }

  /// The page a paragraph falls on: the last page beginning at or before it.
  static _PageStart _pageFor(List<_PageStart> starts, int paraId) {
    var low = 0;
    var high = starts.length - 1;
    var best = starts.first;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (starts[mid].paraId <= paraId) {
        best = starts[mid];
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return best;
  }

  /// ePitaka keeps `<b>`, `<sup>` and `<i>` inside the Pali itself, on about a
  /// quarter of its sentences. Indexing the tag letters would make them
  /// searchable words and throw off distance counts.
  static final _tag = RegExp(r'<[^>]*>');
  static final _space = RegExp(r'\s+');

  static String _clean(String pali) =>
      pali.replaceAll(_tag, ' ').replaceAll(_space, ' ').trim();

  /// The form used for the literal check that exact search makes on top of the
  /// phrase match.
  ///
  /// That check exists to reject what the stemmer matches loosely, and it
  /// compares the search box text against the stored text character by
  /// character. ePitaka punctuates between words where the reader's phrase has
  /// only a space, so "vadeyya. Culasilam" never matches "vadeyya culasilam"
  /// and a correct result is thrown away. Comparing a form with the
  /// punctuation removed keeps the check without that false rejection.
  ///
  /// The same function must be applied to the search phrase, which is why it
  /// is public.
  static final _notPali = RegExp(r'[^0-9a-zāīūṭḍṇṅñṃḷṛ]+');

  static String plainForm(String text) =>
      text.toLowerCase().replaceAll(_notPali, ' ').trim();

  static int _countWords(String text) {
    if (text.isEmpty) return 0;
    return _space.allMatches(text).length + 1;
  }
}

class _PageStart {
  final int paraId;
  final String tprBook;
  final int tprPage;

  const _PageStart(this.paraId, this.tprBook, this.tprPage);
}
