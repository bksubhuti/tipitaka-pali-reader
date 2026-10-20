import 'package:flutter/foundation.dart';
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

  /// Rows written per batch commit.
  ///
  /// Small on purpose. TPR's own indexing has been through this before: on
  /// Android, large batches during a heavy build lost text from the index,
  /// and the hand-written download service settled on 50 (later 200) with a
  /// frame let through after each commit. This follows it.
  static const writesPerCommit = 50;

  /// Bumped when the way the index is built changes enough that an existing
  /// one must be rebuilt. An index without it was built with large batches
  /// and may be missing text while reporting itself complete.
  ///
  /// '3': page starts are placed at the line and word they fall on. Before,
  /// they were placed by paragraph, so a paragraph running across several
  /// pages was filed under the last of them, and a hit in it opened on the
  /// wrong page.
  ///
  /// '4': the three books converted from TPR's own text are indexed too,
  /// from [extraTable]. Before, they could be read but not searched.
  static const format = '4';

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

  /// The translation index keeps vowel signs and other marks inside words.
  ///
  /// By default the tokenizer counts a mark as a gap between words, which
  /// is harmless for Pali in Roman letters but takes Myanmar, Thai, Khmer,
  /// Lao, Sinhala and Hindi apart: စကားစမြည် was stored as the letters
  /// စ က စ မ ည with its vowels gone. A search still matched that run of
  /// letters, loosely, but no word in those languages could be suggested,
  /// since none was stored whole. English is tokenized as before.
  static const _createTranslation = '''
CREATE VIRTUAL TABLE IF NOT EXISTS fts_translation_unit USING FTS5(
  content,
  sutta_name,
  tokenize = "porter unicode61 categories 'L* N* Co M*'",
  content = ''
);''';

  /// The same with the default tokenizer, for an SQLite too old to take the
  /// option. The app bundles one that does; this is only a fallback.
  static const _createTranslationPlain = '''
CREATE VIRTUAL TABLE IF NOT EXISTS fts_translation_unit USING FTS5(
  content,
  sutta_name,
  tokenize = 'porter',
  content = ''
);''';

  /// Bumped when the translation index must be rebuilt on its own, without
  /// touching the Pali one. '2' keeps marks inside words.
  static const translationFormat = '2';

  static Future<void> _createTranslationIndex(Database db) async {
    try {
      await db.execute(_createTranslation);
    } catch (e) {
      debugPrint('translation index without marks in words: $e');
      await db.execute(_createTranslationPlain);
    }
  }

  /// Whether the translation index was built the current way.
  static Future<bool> translationIndexCurrent(Database db) async {
    try {
      final rows = await db.rawQuery(
          "SELECT value FROM search_meta WHERE key = 'translation_format'");
      return rows.isNotEmpty && rows.first['value'] == translationFormat;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _recordTranslationFormat(Database db) => db.rawInsert(
      "INSERT OR REPLACE INTO search_meta (key, value) "
      "VALUES ('translation_format', ?)",
      [translationFormat]);

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
    final tables = await db.rawQuery("SELECT count(*) AS n FROM sqlite_master "
        "WHERE type='table' AND name='fts_unit'");
    if ((tables.first['n'] as int) == 0) return false;
    final side = await db.rawQuery("SELECT count(*) AS n FROM sqlite_master "
        "WHERE type='table' AND name IN ('search_unit', 'search_meta')");
    // An index from before the text was dropped has no side tables, and
    // cannot be searched by the current queries. Treat it as not built so it
    // is replaced.
    if ((side.first['n'] as int) < 2) return false;

    // Finished, not merely started.
    final done =
        await db.rawQuery("SELECT value FROM search_meta WHERE key = 'units'");
    if (done.isEmpty) return false;
    final expected = int.tryParse(done.first['value'] as String? ?? '') ?? 0;
    if (expected <= 0) return false;

    final rows = await db.rawQuery('SELECT count(*) AS n FROM search_unit');
    if ((rows.first['n'] as int) < expected) return false;

    // Built the current way, not merely finished.
    final built =
        await db.rawQuery("SELECT value FROM search_meta WHERE key = 'format'");
    return built.isNotEmpty && built.first['value'] == format;
  }

  /// The languages the translation index was built from, in order.
  ///
  /// Read from `search_meta`, which is written only once a language has been
  /// indexed to the end, so one cut off part way reads as not indexed and is
  /// done again. An index from before that record existed falls back to the
  /// languages its rows name.
  static Future<List<String>> indexedLanguages(Database db) async {
    try {
      final meta = await db
          .rawQuery("SELECT value FROM search_meta WHERE key = 'languages'");
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
    final units = await db
        .rawQuery('SELECT id, epi_book, start_para, end_para FROM search_unit '
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
    final lastIndexed = Sqflite.firstIntValue(
            await db.rawQuery('SELECT max(rowid) FROM fts_translation_unit')) ??
        0;
    final lastMapped = Sqflite.firstIntValue(await db
            .rawQuery('SELECT max(rowid_) FROM search_translation_unit')) ??
        0;
    var rowId = lastIndexed > lastMapped ? lastIndexed : lastMapped;

    var indexed = 0;
    var done = 0;
    for (final entry in byBook.entries) {
      done++;
      final read = await readParagraphs(
          db, 'lang_$code.sentences', 'translation', entry.key);
      if (read.isNotEmpty) {
        // Paragraph texts in order, so each unit takes a contiguous run.
        final paras = [for (final (para, _) in read) para];
        final texts = [for (final (_, text) in read) text];

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
          if (++pending >= writesPerCommit) {
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
    await _createTranslationIndex(db);
    await db.execute(_createTranslationUnit);
    // Recorded empty, then each language as it finishes. Cut off part way,
    // the next start finds the rest missing and adds them; the format is
    // already the new one, so it does not start over.
    await _recordLanguages(db, const []);
    await _recordTranslationFormat(db);
    for (final code in languages) {
      await addLanguage(db, code, onProgress: onProgress);
    }
  }

  /// One book's paragraphs from [table], each as its sentences' [column]
  /// joined in line order and cleaned, in paragraph order. Paragraphs that
  /// come out empty are left out.
  ///
  /// Read a sentence at a time and joined here. Having SQLite join them
  /// (`group_concat ... ORDER BY`) was tried and measured slower, and it
  /// needs SQLite 3.44, which is more than every device can be counted on
  /// for.
  static Future<List<(int, String)>> readParagraphs(
      Database db, String table, String column, String book) async {
    final rows = await db.rawQuery(
      'SELECT para_id, $column AS text FROM $table WHERE book_id = ? '
      'ORDER BY para_id, line_id',
      [book],
    );
    final result = <(int, String)>[];
    for (final row in rows) {
      final text = clean(row['text'] as String? ?? '');
      if (text.isEmpty) continue;
      final para = row['para_id'] as int;
      if (result.isNotEmpty && result.last.$1 == para) {
        result[result.length - 1] = (para, '${result.last.$2} $text');
      } else {
        result.add((para, text));
      }
    }
    return result;
  }

  /// As [readParagraphs], and also where each line starts in its paragraph,
  /// as (line, words before it). A page can begin part-way through a
  /// paragraph, and placing it needs the line it begins on turned into a word
  /// offset. Lines that come out empty are left out, as their words are.
  /// The few books ePitaka does not carry, converted from TPR's own text:
  /// Saddanīti (suttamālā), Kaccāyanasāra and Saddatthabhedacintā. Their
  /// sentences are in the extension under TPR's book ids. The reader shows
  /// them from there, and the index left them out because it only read
  /// ePitaka's sentences, so they opened but no search could find them.
  static const extraTable = 'ext.extra_sentence';

  static Future<List<Map<String, Object?>>> _extraBooks(Database db) async {
    try {
      return await db.rawQuery(
          'SELECT DISTINCT book_id FROM $extraTable ORDER BY book_id');
    } catch (_) {
      // An extension from before the table existed.
      return const [];
    }
  }

  static Future<List<(int, String, List<(int, int)>)>> _readParagraphLines(
      Database db, String table, String column, String book) async {
    List<Map<String, Object?>> rows;
    try {
      rows = await db.rawQuery(
        'SELECT para_id, line_id, $column AS text FROM $table '
        'WHERE book_id = ? ORDER BY para_id, line_id',
        [book],
      );
    } catch (_) {
      if (table != extraTable) rethrow;
      return const [];
    }
    final result = <(int, String, List<(int, int)>)>[];
    var words = 0;
    for (final row in rows) {
      final text = clean(row['text'] as String? ?? '');
      if (text.isEmpty) continue;
      final para = row['para_id'] as int;
      final line = row['line_id'] as int;
      if (result.isNotEmpty && result.last.$1 == para) {
        final last = result.last;
        last.$3.add((line, words));
        result[result.length - 1] = (para, '${last.$2} $text', last.$3);
      } else {
        words = 0;
        result.add((para, text, [(line, 0)]));
      }
      words += _countWords(text);
    }
    return result;
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
    await _createTranslationIndex(db);
    await db.execute(_createUnit);
    await db.execute(_createTranslationUnit);
    await db.execute(_createMeta);

    final pageStarts = await _pageStarts(db);
    final books = [
      ...await db.rawQuery(
          'SELECT DISTINCT book_id FROM epi.sentences ORDER BY book_id'),
      ...await _extraBooks(db),
    ];

    final ids = _Ids();
    var indexed = 0;
    var done = 0;
    for (final bookRow in books) {
      final book = bookRow['book_id'] as String;
      done++;
      final units = await _unitsOf(db, book, pageStarts[book], languages);
      await _write(db, units, ids);
      indexed += units.length;

      if (onProgress != null && done % 2 == 0) {
        onProgress('Building search index: '
            '${(done / books.length * 100).round()}%');
      }
    }
    final unitId = ids.unit;

    // Written last, so it is only there if everything before it finished.
    await db.rawInsert(
        "INSERT OR REPLACE INTO search_meta (key, value) VALUES ('units', ?)",
        ['$unitId']);
    await db.rawInsert(
        "INSERT OR REPLACE INTO search_meta (key, value) VALUES ('format', ?)",
        [format]);
    await _recordTranslationFormat(db);
    await _recordLanguages(db, languages);

    onProgress?.call('Search index built');
    return indexed;
  }

  /// Where each page begins, by ePitaka book, so a result can open in the
  /// reader. The reader is addressed by book and page, and that numbering is
  /// unchanged by the migration, so every unit records the page it starts on.
  static Future<Map<String, List<_PageStart>>> _pageStarts(Database db,
      [List<String>? books]) async {
    final where = books == null
        ? ''
        : 'WHERE book_id IN (${List.filled(books.length, '?').join(',')}) ';
    final breaks = await db.rawQuery(
      'SELECT book_id, para_id, line_id, word_index, tpr_book, tpr_page '
      'FROM ext.page_break $where'
      'ORDER BY book_id, para_id, line_id, word_index',
      books ?? const [],
    );
    final pageStarts = <String, List<_PageStart>>{};
    for (final row in breaks) {
      pageStarts
          .putIfAbsent(row['book_id'] as String, () => <_PageStart>[])
          .add(_PageStart(
            row['para_id'] as int,
            row['line_id'] as int,
            row['word_index'] as int? ?? 0,
            row['tpr_book'] as String,
            row['tpr_page'] as int,
          ));
    }
    return pageStarts;
  }

  /// One book cut into units, with the page each starts on and its
  /// translations, ready to write. Empty for a book TPR has no pages for: a
  /// result in one could not be opened, so it is left out rather than
  /// returned as a dead end.
  static Future<List<_Unit>> _unitsOf(Database db, String book,
      List<_PageStart>? starts, List<String> languages) async {
    if (starts == null || starts.isEmpty) return const [];

    final paragraphs = <int, String>{};
    final lineStarts = <int, List<(int, int)>>{};
    final order = <int>[];
    var read = await _readParagraphLines(db, 'epi.sentences', 'pali', book);
    if (read.isEmpty) {
      read = await _readParagraphLines(db, extraTable, 'pali', book);
    }
    for (final (para, text, lines) in read) {
      paragraphs[para] = text;
      lineStarts[para] = lines;
      order.add(para);
    }
    if (order.isEmpty) return const [];

    // Translations for this book, per language, grouped the same way. Built
    // from the same paragraph boundaries as the Pali rather than from the
    // translation's own lengths, so a unit means the same passage in every
    // language and a hit in one can be shown against the other.
    final byLanguage = <String, Map<int, String>>{};
    for (final code in languages) {
      final map = <int, String>{};
      try {
        for (final (para, text) in await readParagraphs(
            db, 'lang_$code.sentences', 'translation', book)) {
          map[para] = text;
        }
      } catch (_) {
        // A language that will not answer is left out of the index.
      }
      if (map.isNotEmpty) byLanguage[code] = map;
    }

    final units = <_Unit>[];
    var i = 0;
    while (i < order.length) {
      var words = 0;
      var j = i;
      final content = StringBuffer();
      while (j < order.length && (j == i || words < targetWords)) {
        final text = paragraphs[order[j]]!;
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
      //
      // Placed at the line and word each page starts on, not by paragraph:
      // a paragraph can run across several pages, and placed by paragraph
      // it was filed under the last of them.
      final firstPara = order[i];
      final firstLine = lineStarts[firstPara]!.first.$1;
      final at = _lastAtOrBefore(starts, firstPara, firstLine, 0);
      final page = at >= 0 ? starts[at] : starts.first;
      final map = StringBuffer('0:${page.tprPage}');
      var offset = 0;
      var lastPage = page.tprPage;
      var next = at + 1;
      for (var k = i; k < j; k++) {
        final para = order[k];
        final paraWords = _countWords(paragraphs[para]!);
        while (next < starts.length && starts[next].paraId <= para) {
          final start = starts[next++];
          // A page starting in a paragraph with no text, between this one
          // and the last, starts where this one does.
          final within = start.paraId < para
              ? 0
              : (_lineOffset(lineStarts[para]!, start.lineId, paraWords) +
                      start.wordIndex)
                  .clamp(0, paraWords);
          if (start.tprPage != lastPage) {
            map.write(',${offset + within}:${start.tprPage}');
            lastPage = start.tprPage;
          }
        }
        offset += paraWords;
      }

      final translations = <String, String>{};
      for (final entry in byLanguage.entries) {
        final translated = StringBuffer();
        for (var k = i; k < j; k++) {
          final text = entry.value[order[k]];
          if (text == null || text.isEmpty) continue;
          if (translated.isNotEmpty) translated.write(' ');
          translated.write(text);
        }
        if (translated.isNotEmpty) {
          translations[entry.key] = translated.toString();
        }
      }

      units.add(_Unit(
        text: content.toString(),
        tprBook: page.tprBook,
        page: page.tprPage,
        pageMap: map.toString(),
        epiBook: book,
        startPara: order[i],
        endPara: order[j - 1],
        translations: translations,
      ));

      if (j >= order.length) break;
      // step back one paragraph so nothing falls between two units
      i = (i + 1) > (j - overlapParagraphs) ? i + 1 : j - overlapParagraphs;
    }
    return units;
  }

  /// Writes [units] to the index, numbering them on from [ids].
  static Future<void> _write(Database db, List<_Unit> units, _Ids ids) async {
    // A committed batch is not emptied, so it must be replaced after every
    // commit. Reusing it re-applies everything already written and quietly
    // multiplies the index.
    var batch = db.batch();
    var pending = 0;
    for (final unit in units) {
      final unitId = ++ids.unit;
      batch.insert('fts_unit', {
        'rowid': unitId,
        'content': unit.text,
        'sutta_name': '',
      });
      batch.insert('search_unit', {
        'id': unitId,
        ...unit.placement,
        'paranum': '${unit.startPara}-${unit.endPara}',
        'sutta_name': '',
        'epi_book': unit.epiBook,
        'start_para': unit.startPara,
        'end_para': unit.endPara,
      });
      for (final entry in unit.translations.entries) {
        // The translation index has its own row numbering: one unit yields
        // a row per language, so its rowids cannot be the unit's.
        final translationRowId = ++ids.translation;
        batch.insert('fts_translation_unit', {
          'rowid': translationRowId,
          'content': entry.value,
          'sutta_name': '',
        });
        batch.insert('search_translation_unit', {
          'rowid_': translationRowId,
          'unit_id': unitId,
          'lang': entry.key,
        });
        pending++;
      }
      if (++pending >= writesPerCommit) {
        await batch.commit(noResult: true);
        // Let a frame through between batches, as the old download
        // service did, so the screen keeps moving during a long build.
        await Future.delayed(Duration.zero);
        batch = db.batch();
        pending = 0;
      }
    }
    if (pending > 0) await batch.commit(noResult: true);
  }

  /// Brings the index up to date for [books] alone, after an extension
  /// package has added, changed or removed their pages.
  ///
  /// Where a book is indexed already and its text cuts into the same units,
  /// only the pages are rewritten: the units are cut from the sentences,
  /// which a package does not change, so the indexed text is still right.
  /// Otherwise its units are taken out of `search_unit` and written again.
  ///
  /// The text index keeps no copy of what it indexed, so its rows cannot be
  /// deleted. Units taken out are left there unreferenced; every search
  /// reaches the index through `search_unit`, so they are never returned,
  /// and new units are numbered past them.
  ///
  /// Does nothing when there is no finished index: the full build, when it
  /// runs, reads the pages as they are then.
  static Future<int> reindexBooks(Database db, List<String> books,
      {List<String> languages = const []}) async {
    if (books.isEmpty || !await isBuilt(db)) return 0;
    final pageStarts = await _pageStarts(db, books);
    final ids = _Ids(
      unit: await _maxOf(db, 'SELECT max(rowid) AS n FROM fts_unit'),
      translation:
          await _maxOf(db, 'SELECT max(rowid) AS n FROM fts_translation_unit'),
    );
    var changed = 0;
    for (final book in books) {
      final units = await _unitsOf(db, book, pageStarts[book], languages);
      final existing = await db.rawQuery(
          'SELECT id, start_para, end_para FROM search_unit '
          'WHERE epi_book = ? ORDER BY id',
          [book]);
      final sameCut = existing.length == units.length &&
          [
            for (var k = 0; k < units.length; k++)
              existing[k]['start_para'] == units[k].startPara &&
                  existing[k]['end_para'] == units[k].endPara
          ].every((same) => same);

      if (sameCut && units.isNotEmpty) {
        var batch = db.batch();
        for (var k = 0; k < units.length; k++) {
          batch.update('search_unit', units[k].placement,
              where: 'id = ?', whereArgs: [existing[k]['id']]);
          if ((k + 1) % writesPerCommit == 0) {
            await batch.commit(noResult: true);
            await Future.delayed(Duration.zero);
            batch = db.batch();
          }
        }
        await batch.commit(noResult: true);
      } else {
        if (existing.isNotEmpty) {
          await db.execute(
              'DELETE FROM search_translation_unit WHERE unit_id IN '
              '(SELECT id FROM search_unit WHERE epi_book = ?)',
              [book]);
          await db
              .execute('DELETE FROM search_unit WHERE epi_book = ?', [book]);
        }
        await _write(db, units, ids);
      }
      changed += units.length;
    }

    // The count a finished build is checked against. Units taken out leave
    // gaps in the numbering, so it is the number of rows, not the last id.
    final count = await _maxOf(db, 'SELECT count(*) AS n FROM search_unit');
    await db.rawInsert(
        "INSERT OR REPLACE INTO search_meta (key, value) VALUES ('units', ?)",
        ['$count']);
    return changed;
  }

  static Future<int> _maxOf(Database db, String sql) async =>
      ((await db.rawQuery(sql)).first['n'] as int?) ?? 0;

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
  /// The index of the last page start at or before word [word] of line
  /// [line] in paragraph [para], or -1 if every page starts after it.
  static int _lastAtOrBefore(
      List<_PageStart> starts, int para, int line, int word) {
    var low = 0;
    var high = starts.length - 1;
    var best = -1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (starts[mid].compareTo(para, line, word) <= 0) {
        best = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return best;
  }

  /// Words before line [lineId] in a paragraph whose lines start as
  /// [lines]. A line left out for having no text starts where the next one
  /// with text does, or at the end of the paragraph.
  static int _lineOffset(List<(int, int)> lines, int lineId, int paraWords) {
    for (final (line, words) in lines) {
      if (line >= lineId) return words;
    }
    return paraWords;
  }

  /// ePitaka keeps `<b>`, `<sup>` and `<i>` inside the Pali itself, on about a
  /// quarter of its sentences. Indexing the tag letters would make them
  /// searchable words and throw off distance counts.
  static final _tag = RegExp(r'<[^>]*>');
  static final _space = RegExp(r'\s+');

  @visibleForTesting
  static String clean(String pali) {
    final untagged = pali.contains('<') ? _replaceTags(pali) : pali;
    return _isClean(untagged)
        ? untagged
        : untagged.replaceAll(_space, ' ').trim();
  }

  /// Tags to spaces, runs of white space to one space, trimmed: what [clean]
  /// does, written as the two patterns it used to be.
  ///
  /// The patterns cost most of a build: 11 of 13 seconds of reading the
  /// canon went on them, against under 2 for the queries. So [clean] takes
  /// tags out with a plain loop and leaves the text alone when its spacing
  /// is already single, which it nearly always is. A test runs both on every
  /// sentence of the real data and finds no difference.
  @visibleForTesting
  static String cleanByPattern(String pali) =>
      pali.replaceAll(_tag, ' ').replaceAll(_space, ' ').trim();

  /// Each tag to a space, exactly as `<[^>]*>` replaces them: from a `<` to
  /// the first `>` after it. A `<` with no `>` after it is left as it is.
  static String _replaceTags(String text) {
    final buffer = StringBuffer();
    var i = 0;
    while (i < text.length) {
      final open = text.indexOf('<', i);
      if (open < 0) break;
      final close = text.indexOf('>', open + 1);
      if (close < 0) break;
      buffer
        ..write(text.substring(i, open))
        ..write(' ');
      i = close + 1;
    }
    buffer.write(text.substring(i));
    return buffer.toString();
  }

  /// True when [cleanByPattern] would return [text] unchanged: no tag, no
  /// white space at either end, and none but single plain spaces inside.
  static bool _isClean(String text) {
    if (text.isEmpty) return true;
    var previousSpace = true; // so a space at the start counts as a run
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit == 0x3C) return false; // '<'
      if (unit == 0x20) {
        if (previousSpace) return false;
        previousSpace = true;
      } else if (_isOtherSpace(unit)) {
        return false;
      } else {
        previousSpace = false;
      }
    }
    return !previousSpace; // a space at the end
  }

  /// White space other than the plain space, as `\s` in a Dart pattern
  /// matches it, and 0x85, which `\s` does not match but `trim` removes.
  /// Counting that one too only sends such text the long way round.
  static bool _isOtherSpace(int unit) =>
      (unit >= 0x09 && unit <= 0x0D) ||
      unit == 0x85 ||
      unit == 0xA0 ||
      unit == 0x1680 ||
      (unit >= 0x2000 && unit <= 0x200A) ||
      unit == 0x2028 ||
      unit == 0x2029 ||
      unit == 0x202F ||
      unit == 0x205F ||
      unit == 0x3000 ||
      unit == 0xFEFF;

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

/// Ids handed out while writing units, carried on from book to book.
class _Ids {
  int unit;
  int translation;
  _Ids({this.unit = 0, this.translation = 0});
}

/// One unit of the index, before it is written.
class _Unit {
  final String text;
  final String tprBook;
  final int page;
  final String pageMap;
  final String epiBook;
  final int startPara;
  final int endPara;
  final Map<String, String> translations;

  const _Unit({
    required this.text,
    required this.tprBook,
    required this.page,
    required this.pageMap,
    required this.epiBook,
    required this.startPara,
    required this.endPara,
    required this.translations,
  });

  /// Where the unit opens in the reader: the columns that follow the pages.
  Map<String, Object?> get placement =>
      {'bookid': tprBook, 'page': page, 'page_map': pageMap};
}

class _PageStart {
  final int paraId;
  final int lineId;
  final int wordIndex;
  final String tprBook;
  final int tprPage;

  const _PageStart(
      this.paraId, this.lineId, this.wordIndex, this.tprBook, this.tprPage);

  /// Negative, zero or positive as this start comes before, at or after word
  /// [word] of line [line] in paragraph [para].
  int compareTo(int para, int line, int word) {
    if (paraId != para) return paraId.compareTo(para);
    if (lineId != line) return lineId.compareTo(line);
    return wordIndex.compareTo(word);
  }
}
