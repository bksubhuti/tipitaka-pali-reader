import 'package:flutter/material.dart';

import '../../business_logic/models/book.dart';
import '../../business_logic/models/search_result.dart';
import '../../data/constants.dart';
import '../../ui/screens/home/search_page/search_page.dart';
import '../database/database_helper.dart';
import '../database/sentence_fts_builder.dart';
import '../database/unit_text.dart';
import '../prefs.dart';

abstract class FtsRespository {
  Future<List<SearchResult>> getResults(
      String phrase, QueryMode queryMode, int wordDistance,
      {bool isTranslationSearch = false, bool joinEnglish = true});
}

class FtsDatabaseRepository implements FtsRespository {
  final DatabaseHelper databaseHelper;

  /// Which indexes to search. Named rather than hardcoded so the same query
  /// building, snippets and highlighting serve both the page-based index and
  /// the sentence-based one; only the table changes.
  final String paliTable;
  final String translationTable;

  /// Whether to search Pali and the translations together.
  ///
  /// Only for the sentence index: the page index has no populated translation
  /// table to combine with.
  bool get combineLanguages => sentenceIndex;

  /// Whether these are the paragraph-based sentence indexes rather than the
  /// original page ones. They differ in what they can be asked for.
  final bool sentenceIndex;

  FtsDatabaseRepository(
    this.databaseHelper, {
    this.paliTable = 'fts_pages',
    this.translationTable = 'fts_translation_pages',
    this.sentenceIndex = false,
  });

  @override
  Future<List<SearchResult>> getResults(
      String phrase, QueryMode queryMode, int wordDistance,
      {bool isTranslationSearch = false, bool joinEnglish = true}) async {
    if (isTranslationSearch) {
      return await _querySingleTable(phrase, queryMode, wordDistance,
          isTranslation: true);
    }

    final paliResults = await _querySingleTable(phrase, queryMode, wordDistance,
        isTranslation: false);

    // Search the translations as well, not only when the Pali finds nothing.
    // The two are indexed apart so that translation text cannot corrupt word
    // distance on the Pali side, but a reader asking for a word wants it found
    // wherever it is, which is what searching both and merging gives back.
    if (!combineLanguages) {
      if (paliResults.isNotEmpty) return paliResults;
      return await _querySingleTable(phrase, queryMode, wordDistance,
          isTranslation: true);
    }

    final translationResults = await _querySingleTable(
        phrase, queryMode, wordDistance,
        isTranslation: true);

    // Neither language holds the whole phrase. It may still be a query that
    // mixes them, which no single index can answer because a phrase match
    // cannot span two tables. Those are worth one more attempt.
    if (paliResults.isEmpty && translationResults.isEmpty) {
      return await _mixedLanguageSearch(phrase);
    }
    if (translationResults.isEmpty) return paliResults;

    // Pali first, then any passage the translation found that the Pali did
    // not, so the same passage is not listed twice for matching in both.
    final seen = <String>{
      for (final r in paliResults) '${r.book.id}.${r.pageNumber}'
    };
    final merged = <SearchResult>[...paliResults];
    for (final result in translationResults) {
      if (seen.add('${result.book.id}.${result.pageNumber}')) {
        merged.add(result);
      }
    }
    return merged;
  }

  Future<List<SearchResult>> _querySingleTable(
      String phrase, QueryMode queryMode, int wordDistance,
      {required bool isTranslation}) async {
    // The sentence indexes hold no text, so they are searched differently.
    // The page index path below is untouched and still works as it did.
    if (sentenceIndex) {
      return _queryContentless(phrase, queryMode, wordDistance,
          isTranslation: isTranslation);
    }
    final results = <SearchResult>[];

    final ftsTable = isTranslation ? translationTable : paliTable;

    // 1. SANITIZE INPUT: Prevents SQL Injection crashes (e.g., taṇhā'ti)
    String safePhrase = phrase.replaceAll("'", "''");
/////////////////////////////////////////////////////////////////////////////
    /// Fix for sutta and vatthu compounds that are written as two words
/////////////////////////////////////////////////////////////////////////////
    final originalPhrase = phrase.trim();
    final words = originalPhrase
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    if (!isTranslation && words.length == 2) {
      final second = words[1].toLowerCase();
      if (['sutta', 'suttam', 'suttā', 'vatthu', 'vatthuṃ'].contains(second)) {
        final compound = words[0] + words[1]; // kāyagatāsati + sutta
        final compoundResults = await _runPrefixSearch(compound);

        if (compoundResults.isNotEmpty) {
          results.addAll(compoundResults); // Add compound results to the list
        }
      }
    }
    /////////////////////////////////////////////////////////////////////////////

    final db = await databaseHelper.database;

    late String sql;

    if (queryMode == QueryMode.exact) {
      sql = '''
      SELECT $ftsTable.id, $ftsTable.bookid, books.name, $ftsTable.page, $ftsTable.content, $ftsTable.sutta_name${_pageMapColumn(ftsTable)}
      FROM $ftsTable INNER JOIN books ON $ftsTable.bookid = books.id
        LEFT JOIN sutta_page_shortcut
            ON $ftsTable.bookid = sutta_page_shortcut.book_id
            AND $ftsTable.page BETWEEN sutta_page_shortcut.start_page AND sutta_page_shortcut.end_page
      WHERE $ftsTable MATCH '"$safePhrase"'${_exactFilter(ftsTable, originalPhrase)}
      ORDER BY books.sort_order ASC
      ''';
    }

    if (queryMode == QueryMode.prefix) {
      final value = '$safePhrase '.replaceAll(' ', '* ').trim();
      // FIX: Prefix now uses SNIPPET to get the long description from SQLite
      sql = '''
      SELECT $ftsTable.id, $ftsTable.bookid, books.name, $ftsTable.page, $ftsTable.sutta_name,
        SNIPPET($ftsTable, -1, '<$highlightTagName>', '</$highlightTagName>', '...', 25) AS content
      FROM $ftsTable INNER JOIN books ON $ftsTable.bookid = books.id
        LEFT JOIN sutta_page_shortcut
            ON $ftsTable.bookid = sutta_page_shortcut.book_id
            AND $ftsTable.page BETWEEN sutta_page_shortcut.start_page AND sutta_page_shortcut.end_page
      WHERE $ftsTable MATCH '$value'
      ORDER BY books.sort_order ASC
      ''';
    }

    if (queryMode == QueryMode.distance) {
      final words = safePhrase.split(' ').where((w) => w.isNotEmpty);
      final formattedWords = words.map((w) => '"$w"*').join(' ');
      final value = 'NEAR($formattedWords, $wordDistance)';

      sql = '''
      SELECT $ftsTable.id, $ftsTable.bookid, books.name, $ftsTable.page, $ftsTable.sutta_name,
        SNIPPET($ftsTable, -1, '<$highlightTagName>', '</$highlightTagName>', '...', 25) AS content
      FROM $ftsTable 
      INNER JOIN books ON $ftsTable.bookid = books.id
      LEFT JOIN sutta_page_shortcut
          ON $ftsTable.bookid = sutta_page_shortcut.book_id
          AND $ftsTable.page BETWEEN sutta_page_shortcut.start_page AND sutta_page_shortcut.end_page
      WHERE $ftsTable MATCH '$value'
      ORDER BY books.sort_order ASC
      ''';
    }

    if (queryMode == QueryMode.anywhere) {
      // Anywhere MUST use the raw content and LIKE operator
      sql = '''
      SELECT $ftsTable.id, $ftsTable.bookid, books.name, $ftsTable.page, $ftsTable.content, $ftsTable.sutta_name
      FROM $ftsTable INNER JOIN books ON $ftsTable.bookid = books.id
        LEFT JOIN sutta_page_shortcut
            ON $ftsTable.bookid = sutta_page_shortcut.book_id
            AND $ftsTable.page BETWEEN sutta_page_shortcut.start_page AND sutta_page_shortcut.end_page
      WHERE $ftsTable.content LIKE '%$safePhrase%'
      ORDER BY books.sort_order ASC
      ''';
    }

    var maps = await db.rawQuery(sql);

    // --- Result Parsing ---

    var regexMatchWords = _createExactMatch(phrase);
    if (queryMode == QueryMode.prefix) {
      regexMatchWords = _createPrefixMatch(phrase);
    }

    for (var element in maps) {
      final id = element['id'] as int;
      final bookId = element['bookid'] as String;
      final bookName = element['name'] as String;
      final unitPage = element['page'] as int;
      var content = element['content'] as String;
      final suttaName = (element['sutta_name'] as String?) ?? 'n/a';
      final pageMap = element['page_map'] as String?;
      // where the phrase sits in this unit, in words
      final at = RegExp(_phrasePattern(phrase), caseSensitive: false)
          .firstMatch(content);
      final pageNumber = at == null
          ? unitPage
          : pageForMatch(pageMap, unitPage,
              content.substring(0, at.start).split(RegExp(r'\s+')).length - 1);

      // ==========================================
      // EXACT, PREFIX, and DISTANCE all use the DB Snippet
      // ==========================================
      if (queryMode == QueryMode.distance || queryMode == QueryMode.prefix) {
        results.add(SearchResult(
          id: id,
          book: Book(id: bookId, name: bookName),
          pageNumber: pageNumber,
          description: content,
          suttaName: suttaName,
          isTranslation: isTranslation,
        ));
        continue;
      }

      // ==========================================
      // ANYWHERE MODE (Manual Highlight & Extract)
      // ==========================================

      content = _buildHighlight(content, phrase);
      final matches = regexMatchWords.allMatches(content);

      if (matches.isNotEmpty) {
        for (var match in matches) {
          final String description =
              _extractDescription(content, match.start, match.end);

          results.add(SearchResult(
            id: id,
            book: Book(id: bookId, name: bookName),
            pageNumber: pageNumber,
            description: description,
            suttaName: suttaName,
            isTranslation: isTranslation,
          ));
        }
      } else if (queryMode == QueryMode.anywhere) {
        results.add(SearchResult(
          id: id,
          book: Book(id: bookId, name: bookName),
          pageNumber: pageNumber,
          description: _getRightHandSideWords(content, 25),
          suttaName: suttaName,
          isTranslation: isTranslation,
        ));
      }
    }

    // Batch enrich parallel translations for Pali results
    if (!isTranslation && results.isNotEmpty) {
      final ids = results.map((r) => r.id).toSet().join(',');
      final transMaps = await db.rawQuery(
          'SELECT rowid AS id, content FROM $translationTable WHERE rowid IN ($ids)');

      final transMap = <int, String>{};
      for (var row in transMaps) {
        var content = row['content'] as String;
        if (content.length > 250) {
          content = '${content.substring(0, 250)}...';
        }
        transMap[row['id'] as int] = content;
      }

      for (int i = 0; i < results.length; i++) {
        final r = results[i];
        if (transMap.containsKey(r.id)) {
          results[i] = SearchResult(
            id: r.id,
            book: r.book,
            pageNumber: r.pageNumber,
            description: r.description,
            suttaName: r.suttaName,
            isTranslation: r.isTranslation,
            translation: transMap[r.id],
          );
        }
      }
    }

    // Deduplicate results by ID
    final uniqueResults = <SearchResult>[];
    final seenIds = <int>{};
    for (var r in results) {
      if (!seenIds.contains(r.id)) {
        seenIds.add(r.id);
        uniqueResults.add(r);
      }
    }

    debugPrint('total results (${ftsTable}): ${uniqueResults.length}');
    return uniqueResults;
  }

  String _extractDescription(String content, int start, int end) {
    final word = content.substring(start, end);
    // INCREASED: from 8 to 20 so 'anywhere' matches the visual length of the others
    const wordCountForDescription = 20;

    final leftText = _geLeftHandSideWords(
        content.substring(0, start), wordCountForDescription);
    final rightText = _getRightHandSideWords(
        content.substring(end, content.length), wordCountForDescription);

    return '$leftText $word $rightText';
  }

  String _geLeftHandSideWords(String text, int count) {
    if (text.isEmpty) return text;
    final regexAlternateText = RegExp(r'\[.+?\]');
    text = text.replaceAll(regexAlternateText, '');

    final words = <String>[];
    final wordList = text.split(' ');
    final wordCounts = wordList.length;

    for (int i = 1; i <= count; i++) {
      final index = wordCounts - i;
      if (index >= 0) {
        words.add(wordList[index]);
      }
    }
    return words.reversed.join(' ');
  }

  String _getRightHandSideWords(String text, int count) {
    if (text.isEmpty) return text;
    final regexAlternateText = RegExp(r'\[.+?\]');
    text = text.replaceAll(regexAlternateText, '');

    final words = <String>[];
    final wordList = text.split(' ');
    final wordCounts = wordList.length;
    for (int i = 0; i < count; i++) {
      if (i < wordCounts) {
        words.add(wordList[i]);
      }
    }
    return words.join(' ');
  }

  /// Pattern for a phrase, allowing whatever sits between its words.
  ///
  /// A reader types "vadeyya culasilam"; the text reads "vadeyya. Culasilam".
  /// Matching the phrase literally therefore fails, and because exact mode
  /// drops any row whose text it cannot re-match, a correct result is thrown
  /// away after the database has already found it. Treating the gap between
  /// words as "any punctuation and space" fixes that without loosening what
  /// counts as a match: the words themselves, and their order, are unchanged.
  ///
  /// Only used for the sentence index. The page index keeps its old behaviour.
  String _phrasePattern(String phrase) =>
      phrasePattern(phrase, tolerant: sentenceIndex);

  /// The literal check the page index puts on top of a phrase match.
  ///
  /// It is there to reject what the stemmer matches loosely. The sentence
  /// index does not need it: every returned row is re-checked in Dart against
  /// the phrase, which is stricter and tolerates the punctuation that sits
  /// between words in the text. Keeping it in SQL as well meant storing a
  /// second, stripped copy of the whole canon for no gain.
  String _exactFilter(String ftsTable, String phrase) => sentenceIndex
      ? ''
      : " AND $ftsTable.content LIKE '%$phrase%'";

  /// Finds passages holding every word of the query, in either language.
  ///
  /// A reader who types "bhagava Blessed One" is asking for a passage where
  /// the Pali and the English each supply part of what they remember. No
  /// phrase match can answer that: the two languages live in separate indexes
  /// so that translation text cannot corrupt word distance on the Pali side.
  ///
  /// What makes it possible is that a translation unit carries the same id as
  /// the Pali unit it was cut from, so both are the same passage. Each word is
  /// required to appear in that passage in one language or the other, which is
  /// what "mixed, but within the same one" means.
  ///
  /// Word order is not enforced here, unlike a phrase match. A mixed query
  /// cannot have a single order, since the words are not all in one sentence.
  Future<List<SearchResult>> _mixedLanguageSearch(String phrase) async {
    final words = SentenceFtsBuilder.plainForm(phrase)
        .split(' ')
        .where((w) => w.length > 1)
        .toList();
    if (words.length < 2) return const [];

    // One clause per word: present in this passage's Pali or its translation.
    final clauses = <String>[];
    final args = <Object?>[];
    for (final word in words) {
      clauses.add('u.id IN ('
          'SELECT rowid FROM $paliTable WHERE $paliTable MATCH ? '
          'UNION SELECT t.unit_id FROM $translationTable f '
          '  JOIN search_translation_unit t ON t.rowid_ = f.rowid '
          '  WHERE $translationTable MATCH ?)');
      final safe = word.replaceAll('"', '');
      args..add('"$safe"')..add('"$safe"');
    }

    final db = await databaseHelper.database;
    final rows = await db.rawQuery('''
      SELECT u.id, u.bookid, books.name, u.page, u.page_map,
             u.epi_book, u.start_para, u.end_para
      FROM search_unit u INNER JOIN books ON u.bookid = books.id
      WHERE ${clauses.join(' AND ')}
      ORDER BY books.sort_order ASC
      LIMIT 500
    ''', args);

    final results = <SearchResult>[];
    final seen = <String>{};
    for (final row in rows) {
      final content = await UnitText.pali(db,
          epiBook: row['epi_book'] as String,
          startPara: row['start_para'] as int,
          endPara: row['end_para'] as int);
      if (content.isEmpty) continue;
      final bookId = row['bookid'] as String;
      final unitPage = row['page'] as int;

      // Open where the first of the words actually appears, when one of them
      // is in the Pali; otherwise the passage's own page.
      var page = unitPage;
      for (final word in words) {
        final at = RegExp(RegExp.escape(word), caseSensitive: false)
            .firstMatch(content);
        if (at == null) continue;
        page = pageForMatch(row['page_map'] as String?, unitPage,
            content.substring(0, at.start).split(RegExp(r'\s+')).length - 1);
        break;
      }

      if (!seen.add('$bookId.$page')) continue;
      results.add(SearchResult(
        id: row['id'] as int,
        book: Book(id: bookId, name: row['name'] as String),
        pageNumber: page,
        description: _buildHighlight(content, words.first),
        suttaName: 'n/a',
      ));
    }
    return results;
  }

  /// The sentence index records where each page begins inside a unit; the
  /// page index has no such column. Must name the table being searched, not
  /// the Pali one, or a translation search asks the wrong table for it.
  String _pageMapColumn(String ftsTable) =>
      sentenceIndex ? ', $ftsTable.page_map' : '';

  /// The page a match actually sits on.
  ///
  /// A unit is about a page long and overlaps its neighbour, so a match often
  /// falls past the page the unit began on. Reporting the unit's own page
  /// sends the reader to the page before the one holding the text, where it
  /// then cannot find the phrase to highlight.
  static int pageForMatch(String? pageMap, int unitPage, int wordOffset) {
    if (pageMap == null || pageMap.isEmpty) return unitPage;
    var page = unitPage;
    for (final part in pageMap.split(',')) {
      final colon = part.indexOf(':');
      if (colon < 0) continue;
      final at = int.tryParse(part.substring(0, colon));
      final value = int.tryParse(part.substring(colon + 1));
      if (at == null || value == null) continue;
      if (at <= wordOffset) {
        page = value;
      } else {
        break;
      }
    }
    return page;
  }

  /// Public so the behaviour can be tested: it was a silent failure once, and
  /// no automated check caught it.
  static String phrasePattern(String phrase, {required bool tolerant}) {
    if (!tolerant) return RegExp.escape(phrase);
    final words = phrase
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map(RegExp.escape)
        .toList();
    if (words.isEmpty) return RegExp.escape(phrase);
    return words.join(r'[^0-9a-zāīūṭḍṇṅñṃḷṛ]+');
  }

  RegExp _createExactMatch(String phrase) {
    return RegExp(
      '<$highlightTagName>${_phrasePattern(phrase)}</$highlightTagName>',
      caseSensitive: false,
    );
  }

  RegExp _createPrefixMatch(String phrase) {
    final patterns = <String>[];
    final words = phrase.split(' ');
    for (var word in words) {
      patterns.add(
          '<$highlightTagName>${RegExp.escape(word)}.*?</$highlightTagName>');
    }
    return RegExp(patterns.join(' '));
  }

  String _buildHighlight(String content, String phrase) {
    return content.replaceAllMapped(
        RegExp(_phrasePattern(phrase), caseSensitive: false),
        (match) => '<$highlightTagName>${match.group(0)}</$highlightTagName>');
  }

  /// Helper to run a prefix search (used for compound words like kāyagatāsatisutta)
  Future<List<SearchResult>> _runPrefixSearch(String compoundPhrase) async {
    final db = await databaseHelper.database;
    String safe = compoundPhrase.replaceAll("'", "''");
    final value = '$safe '.replaceAll(' ', '* ').trim();

    // Names the configured index rather than fts_pages: once the page data is
    // retired that table is gone, and this was the one query left pointing at
    // it by name.
    final sql = '''
      SELECT $paliTable.id, $paliTable.bookid, name, $paliTable.page, $paliTable.sutta_name,
        $paliTable.content AS raw_content,
        SNIPPET($paliTable, -1, '<$highlightTagName>', '</$highlightTagName>', '...', 25) AS content
        ${_pageMapColumn(paliTable)}
      FROM $paliTable 
      INNER JOIN books ON $paliTable.bookid = books.id
      LEFT JOIN sutta_page_shortcut
          ON $paliTable.bookid = sutta_page_shortcut.book_id
          AND $paliTable.page BETWEEN sutta_page_shortcut.start_page AND sutta_page_shortcut.end_page
      WHERE $paliTable MATCH '$value'
      ORDER BY books.sort_order ASC
    ''';

    final maps = await db.rawQuery(sql);

    final results = <SearchResult>[];
    for (var element in maps) {
      final id = element['id'] as int;
      final bookId = element['bookid'] as String;
      final bookName = element['name'] as String;
      final unitPage = element['page'] as int;
      final content = element['content'] as String;
      final suttaName = (element['sutta_name'] as String?) ?? 'n/a';

      // A unit spans several printed pages, so the page it starts on is not
      // where the match is. Measured on the raw text: the snippet has been
      // cut and tagged, so offsets in it mean nothing.
      final raw = element['raw_content'] as String? ?? '';
      final at = RegExp(RegExp.escape(compoundPhrase.split(' ').first),
              caseSensitive: false)
          .firstMatch(raw);
      final pageNumber = at == null
          ? unitPage
          : pageForMatch(element['page_map'] as String?, unitPage,
              raw.substring(0, at.start).split(RegExp(r'\s+')).length - 1);

      results.add(SearchResult(
        id: id,
        book: Book(id: bookId, name: bookName),
        pageNumber: pageNumber,
        description: content,
        suttaName: suttaName,
      ));
    }
    return results;
  }
  /// Search against the contentless indexes.
  ///
  /// The index knows which units match; it no longer holds their text. So the
  /// shape is: ask the index for the units, read their metadata from
  /// `search_unit`, and rebuild the text of the few that will be shown. The
  /// filtering, the highlight and the page a result opens on are then worked
  /// out here rather than in SQL, which is where exact search already did its
  /// real checking.
  ///
  /// The candidate limit is generous because exact mode discards some of what
  /// the stemmed tokenizer returns; the visible list is far shorter.
  static const _candidateLimit = 500;

  Future<List<SearchResult>> _queryContentless(
      String phrase, QueryMode queryMode, int wordDistance,
      {required bool isTranslation}) async {
    final db = await databaseHelper.database;
    final ftsTable = isTranslation ? translationTable : paliTable;
    final safePhrase = phrase.replaceAll("'", "''");
    final words = phrase
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return const [];

    // "kāyagatāsati sutta" is one word in the text and two in the query. The
    // page index path does this too; it has to be repeated here because the
    // dispatch happens before it.
    final compound = <SearchResult>[];
    if (!isTranslation && words.length == 2) {
      const joined = ['sutta', 'suttam', 'suttā', 'vatthu', 'vatthuṃ'];
      if (joined.contains(words[1].toLowerCase())) {
        compound.addAll(await _queryContentless(
            words[0] + words[1], QueryMode.prefix, wordDistance,
            isTranslation: false));
      }
    }

    final columns = isTranslation
        ? 'u.id, u.bookid, books.name, u.page, u.page_map, u.epi_book, '
            'u.start_para, u.end_para, u.sutta_name, t.lang'
        : 'u.id, u.bookid, books.name, u.page, u.page_map, u.epi_book, '
            'u.start_para, u.end_para, u.sutta_name, NULL AS lang';
    // A translation that is switched off is not searched either. The index
    // holds every installed language, so this is where the reader's choice is
    // applied.
    final shown = _shownLanguages;
    if (isTranslation && shown.isEmpty) return const [];
    final langFilter = isTranslation
        ? " AND t.lang IN (${shown.map((c) => "'$c'").join(',')})"
        : '';

    final joins = isTranslation
        ? 'FROM $ftsTable f '
            'JOIN search_translation_unit t ON t.rowid_ = f.rowid '
            'JOIN search_unit u ON u.id = t.unit_id '
            'JOIN books ON u.bookid = books.id'
        : 'FROM $ftsTable f '
            'JOIN search_unit u ON u.id = f.rowid '
            'JOIN books ON u.bookid = books.id';

    late String sql;
    if (queryMode == QueryMode.anywhere) {
      // Anywhere matches inside words, which no tokenizer will do, so it goes
      // to the sentences themselves. One difference from the old behaviour: a
      // phrase running from one sentence into the next is not found this way,
      // where a scan of whole units would have found it. Anywhere is for
      // partial words, and a partial word does not span a sentence.
      final lang = shown.isEmpty ? null : shown.first;
      if (isTranslation && lang == null) return const [];
      final source = isTranslation
          ? '(SELECT book_id, para_id, translation AS text '
              'FROM lang_$lang.sentences)'
          : '(SELECT book_id, para_id, pali AS text FROM epi.sentences)';
      sql = '''
      SELECT DISTINCT u.id, u.bookid, books.name, u.page, u.page_map,
             u.epi_book, u.start_para, u.end_para, u.sutta_name,
             ${isTranslation ? "'$lang'" : 'NULL'} AS lang
      FROM $source s
      JOIN search_unit u ON u.epi_book = s.book_id
        AND s.para_id BETWEEN u.start_para AND u.end_para
      JOIN books ON u.bookid = books.id
      WHERE s.text LIKE '%$safePhrase%'
      ORDER BY books.sort_order ASC
      LIMIT $_candidateLimit
      ''';
    } else {
      late String match;
      if (queryMode == QueryMode.exact) {
        match = '"$safePhrase"';
      } else if (queryMode == QueryMode.prefix) {
        match = words.map((w) => '"${w.replaceAll('"', '')}"*').join(' ');
      } else {
        final formatted =
            words.map((w) => '"${w.replaceAll('"', '')}"*').join(' ');
        match = 'NEAR($formatted, $wordDistance)';
      }
      sql = '''
      SELECT $columns
      $joins
      WHERE $ftsTable MATCH '$match'$langFilter
      ORDER BY books.sort_order ASC
      LIMIT $_candidateLimit
      ''';
    }

    final rows = await db.rawQuery(sql);
    if (rows.isEmpty) return const [];

    final exactPattern = RegExp(_phrasePattern(phrase), caseSensitive: false);
    final results = <SearchResult>[];

    for (final row in rows) {
      final id = row['id'] as int;
      final lang = row['lang'] as String?;
      final epiBook = row['epi_book'] as String;
      final startPara = row['start_para'] as int;
      final endPara = row['end_para'] as int;

      final content = isTranslation && lang != null
          ? await UnitText.translation(db,
              lang: lang,
              epiBook: epiBook,
              startPara: startPara,
              endPara: endPara)
          : await UnitText.pali(db,
              epiBook: epiBook, startPara: startPara, endPara: endPara);
      if (content.isEmpty) continue;

      // The tokenizer is stemmed, so an exact search has to be re-checked
      // against the words themselves. That used to be a LIKE in SQL; it is
      // the same test, on the same string, in the one place that can still
      // see it.
      final at = exactPattern.firstMatch(content);
      if (queryMode == QueryMode.exact && at == null) continue;

      // Where the hit actually is. For a phrase that is the phrase; for a
      // prefix or distance search the words are scattered and the place worth
      // showing is where they come together.
      final hitAt = at?.start ??
          locateHit(content, words, wordDistance > 0 ? wordDistance : 20);

      final unitPage = row['page'] as int;
      final pageNumber = hitAt < 0
          ? unitPage
          : pageForMatch(row['page_map'] as String?, unitPage,
              content.substring(0, hitAt).split(RegExp(r'\s+')).length - 1);

      final suttaName = (row['sutta_name'] as String?)?.isNotEmpty == true
          ? row['sutta_name'] as String
          : 'n/a';

      final description = _snippetAround(content, hitAt, words);

      results.add(SearchResult(
        id: id,
        book: Book(id: row['bookid'] as String, name: row['name'] as String),
        pageNumber: pageNumber,
        description: description,
        suttaName: suttaName,
        isTranslation: isTranslation,
      ));
    }

    if (!isTranslation && results.isNotEmpty) {
      await _attachTranslations(db, results);
    }

    final unique = <SearchResult>[];
    final seen = <int>{};
    for (final r in [...compound, ...results]) {
      if (seen.add(r.id)) unique.add(r);
    }
    return unique;
  }

  /// Where in this unit the hit is, as an offset into [content].
  ///
  /// A phrase search knows its own answer. A prefix or distance search does
  /// not: its words are spread through the passage, and the first stray
  /// occurrence of one of them is not where the reader wants to land. This
  /// looks for the first place where all of them fall inside [distance]
  /// words of each other, which is what the distance search was asking for.
  ///
  /// Returns -1 when none of the words is present, in which case the caller
  /// keeps the page the unit starts on.
  ///
  /// This replaces what SQLite's snippet() used to do. Without it a distance
  /// search opened at the top of the passage and showed its first words
  /// rather than the match, with nothing marked.
  ///
  /// Public so it can be tested. Where a result opens is not something a
  /// summary count would ever show to be wrong.
  static int locateHit(String content, List<String> words, int distance) {
    if (words.isEmpty) return -1;
    final lower = content.toLowerCase();
    final needles = words.map((w) => w.toLowerCase()).toList();

    // Word starts, so a needle matches the beginning of a word rather than
    // the middle of a longer one.
    final starts = <int>[];
    final tokens = <String>[];
    final separator = RegExp(r'[^0-9a-zāīūṭḍṇṅñṃḷṛ]');
    var i = 0;
    while (i < lower.length) {
      if (separator.hasMatch(lower[i])) {
        i++;
        continue;
      }
      final from = i;
      while (i < lower.length && !separator.hasMatch(lower[i])) {
        i++;
      }
      starts.add(from);
      tokens.add(lower.substring(from, i));
    }
    if (tokens.isEmpty) return -1;

    // Which token positions each needle occurs at, as a prefix.
    final positions = <List<int>>[];
    for (final needle in needles) {
      final found = <int>[];
      for (var t = 0; t < tokens.length; t++) {
        if (tokens[t].startsWith(needle)) found.add(t);
      }
      if (found.isEmpty) return _firstOfAny(tokens, starts, needles);
      positions.add(found);
    }

    // The earliest occurrence of the first word that has all the others
    // within reach of it. The offset returned is the earliest word of that
    // cluster rather than the anchor, so the reader lands at the start of the
    // passage that holds them all and not in the middle of it.
    for (final at in positions.first) {
      var earliest = at;
      var all = true;
      for (var w = 1; w < positions.length; w++) {
        var nearest = -1;
        for (final p in positions[w]) {
          if ((p - at).abs() <= distance) {
            if (nearest < 0 || p < nearest) nearest = p;
          }
        }
        if (nearest < 0) {
          all = false;
          break;
        }
        if (nearest < earliest) earliest = nearest;
      }
      if (all) return starts[earliest];
    }
    return _firstOfAny(tokens, starts, needles);
  }

  /// The first place any of the words occurs, for when they never come
  /// together. Better than the top of the passage.
  static int _firstOfAny(
      List<String> tokens, List<int> starts, List<String> needles) {
    for (var t = 0; t < tokens.length; t++) {
      for (final needle in needles) {
        if (tokens[t].startsWith(needle)) return starts[t];
      }
    }
    return -1;
  }

  /// A window of text around the hit, with every query word marked.
  ///
  /// Each word is marked on its own rather than as a phrase. The result list
  /// showed nothing highlighted for prefix and distance searches because the
  /// phrase pattern needs the words next to each other, and in those two
  /// modes they are not.
  String _snippetAround(String content, int offset, List<String> words) {
    const around = 20;
    final from = offset < 0 ? 0 : offset;
    final left = _geLeftHandSideWords(content.substring(0, from), around);
    final right = _getRightHandSideWords(content.substring(from), around);
    final window = left.isEmpty ? right : '$left $right';

    var marked = window;
    for (final word in words) {
      if (word.isEmpty) continue;
      final pattern = RegExp(
        '(?<![0-9a-zāīūṭḍṇṅñṃḷṛ])${RegExp.escape(word)}'
        '[0-9a-zāīūṭḍṇṅñṃḷṛ]*',
        caseSensitive: false,
      );
      marked = marked.replaceAllMapped(
          pattern,
          (m) => '<$highlightTagName>${m.group(0)}'
              '</$highlightTagName>');
    }
    return marked;
  }

  /// Shows the parallel translation beneath a Pali result, when one is
  /// installed. Rebuilt like everything else rather than read from the index.
  Future<void> _attachTranslations(
      dynamic db, List<SearchResult> results) async {
    final ids = results.map((r) => r.id).toSet().toList();
    if (ids.isEmpty) return;
    final shown = _shownLanguages;
    if (shown.isEmpty) return;
    final langList = shown.map((c) => "'$c'").join(',');
    final placeholders = List.filled(ids.length, '?').join(',');
    List<Map<String, Object?>> rows;
    try {
      rows = await db.rawQuery(
        'SELECT t.unit_id, min(t.lang) AS lang, u.epi_book, u.start_para, '
        '  u.end_para '
        'FROM search_translation_unit t '
        'JOIN search_unit u ON u.id = t.unit_id '
        'WHERE t.unit_id IN ($placeholders) '
        '  AND t.lang IN ($langList) '
        'GROUP BY t.unit_id',
        ids,
      );
    } catch (_) {
      return;
    }

    final byUnit = <int, String>{};
    for (final row in rows) {
      var text = await UnitText.translation(db,
          lang: row['lang'] as String,
          epiBook: row['epi_book'] as String,
          startPara: row['start_para'] as int,
          endPara: row['end_para'] as int);
      if (text.isEmpty) continue;
      if (text.length > 250) text = '${text.substring(0, 250)}...';
      byUnit[row['unit_id'] as int] = text;
    }

    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      final text = byUnit[r.id];
      if (text == null) continue;
      results[i] = SearchResult(
        id: r.id,
        book: r.book,
        pageNumber: r.pageNumber,
        description: r.description,
        suttaName: r.suttaName,
        isTranslation: r.isTranslation,
        translation: text,
      );
    }
  }

  /// The translations the reader has switched on, in display order.
  ///
  /// The index carries every installed language; this is what narrows it to
  /// the ones actually wanted.
  List<String> get _shownLanguages => Prefs.activeLanguages
      .where(DatabaseHelper.installedLanguages.contains)
      .toList();

}
