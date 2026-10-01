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

  /// The indexes hold no text of their own.
  ///
  /// FTS5 keeps a copy of everything it indexes unless told not to, and that
  /// copy was the single largest thing in the database: 713 MB across the two
  /// indexes, against 136 MB for the same indexes without it. The canon is
  /// already on disk in `epi.sentences`, and each translation in its own
  /// file, so storing it a second time bought nothing but the convenience of
  /// SQL-side snippets.
  ///
  /// `content=''` makes them contentless: the terms are indexed, the text is
  /// not kept. A unit's text is rebuilt from the sentences when it is needed,
  /// which is only ever for the handful of rows on screen.
  static const _createPali = '''
CREATE VIRTUAL TABLE IF NOT EXISTS fts_unit USING FTS5(
  content,
  sutta_name,
  tokenize = 'porter',
  content = ''
);''';

  static const _createTranslation = '''
CREATE VIRTUAL TABLE IF NOT EXISTS fts_translation_unit USING FTS5(
  content,
  sutta_name,
  tokenize = 'porter',
  content = ''
);''';

  /// What a contentless index cannot answer: where a unit is, and which
  /// sentences it was made of. Small, because it is integers and short ids
  /// rather than text.
  ///
  /// `epi_book` is stored rather than derived from `bookid`, because 23 of
  /// the 179 TPR books span more than one ePitaka book and the wrong one
  /// rebuilds to nothing.
  static const _createUnit = '''
CREATE TABLE IF NOT EXISTS search_unit (
  id INTEGER PRIMARY KEY,
  bookid TEXT NOT NULL,
  page INTEGER NOT NULL,
  page_map TEXT,
  paranum TEXT,
  sutta_name TEXT,
  epi_book TEXT NOT NULL,
  start_para INTEGER NOT NULL,
  end_para INTEGER NOT NULL
);''';

  /// One row per unit per language, keyed by the translation index's rowid.
  static const _createTranslationUnit = '''
CREATE TABLE IF NOT EXISTS search_translation_unit (
  rowid_ INTEGER PRIMARY KEY,
  unit_id INTEGER NOT NULL,
  lang TEXT NOT NULL
);''';

  /// Records that a build ran to the end.
  ///
  /// Rows alone do not mean a finished index. A build interrupted part way —
  /// the app closed, the device asleep — leaves a table with plenty of rows
  /// in it and no sign that half the canon is missing. Search would then
  /// answer confidently about a fraction of the texts, which is worse than
  /// saying it is not ready.
  static const _createMeta = '''
CREATE TABLE IF NOT EXISTS search_meta (
  key TEXT PRIMARY KEY,
  value TEXT
);''';

  /// True when the index already exists and holds rows.
  static Future<bool> isBuilt(Database db) async {
    final tables = await db.rawQuery(
        "SELECT count(*) AS n FROM sqlite_master "
        "WHERE type='table' AND name='fts_unit'");
    if ((tables.first['n'] as int) == 0) return false;
    final side = await db.rawQuery(
        "SELECT count(*) AS n FROM sqlite_master "
        "WHERE type='table' AND name IN ('search_unit', 'search_meta')");
    // An index from before the text was dropped has no side tables, and
    // cannot be searched by the current queries. Treat it as not built so it
    // is replaced.
    if ((side.first['n'] as int) < 2) return false;

    // Finished, not merely started.
    final done = await db.rawQuery(
        "SELECT value FROM search_meta WHERE key = 'units'");
    if (done.isEmpty) return false;
    final expected = int.tryParse(done.first['value'] as String? ?? '') ?? 0;
    if (expected <= 0) return false;

    final rows = await db.rawQuery('SELECT count(*) AS n FROM search_unit');
    return (rows.first['n'] as int) >= expected;
  }

  /// The languages the translation index was built from, in order.
  ///
  /// Read from `search_meta`, which is written only once a language has been
  /// indexed to the end, so one cut off part way reads as not indexed and is
  /// done again. An index from before that record existed falls back to the
  /// languages its rows name.
  static Future<List<String>> indexedLanguages(Database db) async {
    try {
      final meta = await db.rawQuery(
          "SELECT value FROM search_meta WHERE key = 'languages'");
      if (meta.isNotEmpty) {
        final value = meta.first['value'] as String? ?? '';
        return value.isEmpty ? const [] : (value.split(',')..sort());
      }
      final rows = await db.rawQuery(
          'SELECT DISTINCT lang FROM search_translation_unit ORDER BY lang');
      return rows.map((r) => r['lang'] as String).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _recordLanguages(
      Database db, List<String> languages) async {
    final sorted = [...languages]..sort();
    await db.rawInsert(
        "INSERT OR REPLACE INTO search_meta (key, value) "
        "VALUES ('languages', ?)",
        [sorted.join(',')]);
  }

  /// Indexes one language against the units already built.
  ///
  /// Installing a language used to rebuild the whole index, Pali included,
  /// which is minutes of work for something that does not change the Pali at
  /// all. A unit records which paragraphs of which ePitaka book it covers, so
  /// a translation can be laid over the same units on its own.
  ///
  /// The text is joined the way [UnitText.translation] rebuilds it for the
  /// result list, paragraph range by paragraph range, so the highlight and
  /// the page a result opens on find the same string that was indexed.
  ///
  /// Safe to repeat. Rows a previous, interrupted run left for this language
  /// are taken off first; the contentless index keeps their terms, but
  /// nothing joins to them any more, so they are never returned.
  static Future<int> addLanguage(
    Database db,
    String code, {
    void Function(String message)? onProgress,
  }) async {
    final units = await db.rawQuery(
        'SELECT id, epi_book, start_para, end_para FROM search_unit '
        'ORDER BY epi_book, id');
    final byBook = <String, List<Map<String, Object?>>>{};
    for (final unit in units) {
      byBook.putIfAbsent(unit['epi_book'] as String, () => []).add(unit);
    }

    await db.rawDelete(
        'DELETE FROM search_translation_unit WHERE lang = ?', [code]);
    // Row numbers carry on from the highest ever used, including rows left
    // behind in the index by an earlier run, which a contentless table will
    // not let go of.
    final lastIndexed = Sqflite.firstIntValue(await db
            .rawQuery('SELECT max(rowid) FROM fts_translation_unit')) ??
        0;
    final lastMapped = Sqflite.firstIntValue(await db
            .rawQuery('SELECT max(rowid_) FROM search_translation_unit')) ??
        0;
    var rowId = lastIndexed > lastMapped ? lastIndexed : lastMapped;

    var indexed = 0;
    var done = 0;
    for (final entry in byBook.entries) {
      done++;
      final rows = await db.rawQuery(
        'SELECT para_id, translation FROM lang_$code.sentences '
        'WHERE book_id = ? ORDER BY para_id, line_id',
        [entry.key],
      );
      if (rows.isNotEmpty) {
        // Paragraph texts in order, so each unit takes a contiguous run.
        final paras = <int>[];
        final texts = <String>[];
        for (final row in rows) {
          final text = _clean(row['translation'] as String? ?? '');
          if (text.isEmpty) continue;
          final para = row['para_id'] as int;
          if (paras.isNotEmpty && paras.last == para) {
            texts[texts.length - 1] = '${texts.last} $text';
          } else {
            paras.add(para);
            texts.add(text);
          }
        }

        var batch = db.batch();
        var pending = 0;
        for (final unit in entry.value) {
          final start = unit['start_para'] as int;
          final end = unit['end_para'] as int;
          final buffer = StringBuffer();
          for (var k = _firstAtOrAfter(paras, start);
              k < paras.length && paras[k] <= end;
              k++) {
            if (buffer.isNotEmpty) buffer.write(' ');
            buffer.write(texts[k]);
          }
          if (buffer.isEmpty) continue;
          rowId++;
          batch.insert('fts_translation_unit', {
            'rowid': rowId,
            'content': buffer.toString(),
            'sutta_name': '',
          });
          batch.insert('search_translation_unit', {
            'rowid_': rowId,
            'unit_id': unit['id'],
            'lang': code,
          });
          indexed++;
          if (++pending >= 300) {
            await batch.commit(noResult: true);
            await Future.delayed(Duration.zero);
            batch = db.batch();
            pending = 0;
          }
        }
        if (pending > 0) await batch.commit(noResult: true);
      }

      if (onProgress != null && done % 2 == 0) {
        onProgress('Indexing $code for search: '
            '${(done / byBook.length * 100).round()}%');
      }
    }

    final now = await indexedLanguages(db);
    await _recordLanguages(db, {...now, code}.toList());
    onProgress?.call('Indexed $code for search');
    return indexed;
  }

  /// Takes one language out of search, at once.
  ///
  /// A contentless index cannot delete rows, but it does not need to: a
  /// translation hit is only returned through its row in
  /// `search_translation_unit`, so removing those is enough. The terms left
  /// in the index cost a little space until the next full build, and nothing
  /// else.
  static Future<void> removeLanguage(Database db, String code) async {
    await db.rawDelete(
        'DELETE FROM search_translation_unit WHERE lang = ?', [code]);
    final now = await indexedLanguages(db);
    await _recordLanguages(db, now.where((c) => c != code).toList());
  }

  /// Rebuilds only the translation half of the index, for [languages].
  ///
  /// What removing a language needs: a contentless index cannot delete one
  /// language's rows, but the translation half can be replaced without
  /// touching the Pali, which is most of the work of a full build.
  static Future<void> rebuildTranslations(
    Database db,
    List<String> languages, {
    void Function(String message)? onProgress,
  }) async {
    await db.execute('DROP TABLE IF EXISTS fts_translation_unit;');
    await db.execute('DROP TABLE IF EXISTS search_translation_unit;');
    await db.execute(_createTranslation);
    await db.execute(_createTranslationUnit);
    await _recordLanguages(db, const []);
    for (final code in languages) {
      await addLanguage(db, code, onProgress: onProgress);
    }
  }

  static int _firstAtOrAfter(List<int> sorted, int value) {
    var low = 0;
    var high = sorted.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (sorted[mid] < value) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
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
    await db.execute('DROP TABLE IF EXISTS search_unit;');
    await db.execute('DROP TABLE IF EXISTS search_translation_unit;');
    await db.execute('DROP TABLE IF EXISTS search_meta;');
    await db.execute(_createPali);
    await db.execute(_createTranslation);
    await db.execute(_createUnit);
    await db.execute(_createTranslationUnit);
    await db.execute(_createMeta);

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
    // The translation index has its own row numbering: one unit yields a row
    // per language, so its rowids cannot be the unit's.
    var translationId = 0;
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
        ++unitId;
        batch.insert('fts_unit', {
          'rowid': unitId,
          'content': text,
          'sutta_name': '',
        });
        batch.insert('search_unit', {
          'id': unitId,
          'bookid': page.tprBook,
          'page': page.tprPage,
          'page_map': map.toString(),
          'paranum': '${order[i]}-${order[j - 1]}',
          'sutta_name': '',
          'epi_book': book,
          'start_para': order[i],
          'end_para': order[j - 1],
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
          final translationRowId = ++translationId;
          batch.insert('fts_translation_unit', {
            'rowid': translationRowId,
            'content': translatedText,
            'sutta_name': '',
          });
          batch.insert('search_translation_unit', {
            'rowid_': translationRowId,
            'unit_id': unitId,
            'lang': entry.key,
          });
          pending++;
        }

        indexed++;
        if (++pending >= 300) {
          await batch.commit(noResult: true);
          // Let a frame through between batches, as the old download
          // service did, so the screen keeps moving during a long build.
          await Future.delayed(Duration.zero);
          batch = db.batch();
          pending = 0;
        }

        if (j >= order.length) break;
        // step back one paragraph so nothing falls between two units
        i = (i + 1) > (j - overlapParagraphs) ? i + 1 : j - overlapParagraphs;
      }
      if (pending > 0) await batch.commit(noResult: true);

      if (onProgress != null && done % 2 == 0) {
        onProgress('Building search index: '
            '${(done / books.length * 100).round()}%');
      }
    }

    // Written last, so it is only there if everything before it finished.
    await db.rawInsert(
        "INSERT OR REPLACE INTO search_meta (key, value) VALUES ('units', ?)",
        ['$unitId']);
    await _recordLanguages(db, languages);

    onProgress?.call('Search index built');
    return indexed;
  }

  /// Removes a half-written index.
  ///
  /// A build that fails part way leaves rows behind, and rows are what the
  /// app reads as "there is an index here". Search would then run against a
  /// fraction of the canon and say it had found everything. Better to have
  /// none and build it again.
  static Future<void> discard(Database db) async {
    for (final table in const [
      'fts_unit',
      'fts_translation_unit',
      'search_unit',
      'search_translation_unit',
      'search_meta',
    ]) {
      try {
        await db.execute('DROP TABLE IF EXISTS $table');
      } catch (_) {
        // Nothing useful to do; the next build drops them again anyway.
      }
    }
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

  /// Words of a phrase, punctuation and case removed.
  ///
  /// Used to split a query, not to store anything: an earlier version kept a
  /// stripped copy of every unit so the database could do a literal check.
  /// That doubled the index for no gain, because exact search re-checks the
  /// phrase in Dart anyway, and more strictly.
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
