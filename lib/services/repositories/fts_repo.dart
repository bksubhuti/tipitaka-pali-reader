import 'package:flutter/material.dart';

import '../../business_logic/models/book.dart';
import '../../business_logic/models/search_result.dart';
import '../../data/constants.dart';
import '../../ui/screens/home/search_page/search_page.dart';
import '../database/database_helper.dart';
import '../database/sentence_fts_builder.dart';

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
          'SELECT id FROM $paliTable WHERE $paliTable MATCH ? '
          'UNION SELECT id FROM $translationTable '
          'WHERE $translationTable MATCH ?)');
      final safe = word.replaceAll('"', '');
      args..add('"$safe"')..add('"$safe"');
    }

    final rows = await (await databaseHelper.database).rawQuery('''
      SELECT u.id, u.bookid, books.name, u.page, u.content, u.page_map
      FROM $paliTable u INNER JOIN books ON u.bookid = books.id
      WHERE ${clauses.join(' AND ')}
      ORDER BY books.sort_order ASC
      LIMIT 500
    ''', args);

    final results = <SearchResult>[];
    final seen = <String>{};
    for (final row in rows) {
      final content = row['content'] as String;
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

    final sql = '''
      SELECT fts_pages.id, fts_pages.bookid, name, fts_pages.page, fts_pages.sutta_name,
        SNIPPET(fts_pages, -1, '<$highlightTagName>', '</$highlightTagName>', '...', 25) AS content
      FROM fts_pages 
      INNER JOIN books ON fts_pages.bookid = books.id
      LEFT JOIN sutta_page_shortcut
          ON fts_pages.bookid = sutta_page_shortcut.book_id
          AND fts_pages.page BETWEEN sutta_page_shortcut.start_page AND sutta_page_shortcut.end_page
      WHERE fts_pages MATCH '$value'
      ORDER BY books.sort_order ASC
    ''';

    final maps = await db.rawQuery(sql);

    final results = <SearchResult>[];
    for (var element in maps) {
      final id = element['id'] as int;
      final bookId = element['bookid'] as String;
      final bookName = element['name'] as String;
      final pageNumber = element['page'] as int;
      final content = element['content'] as String;
      final suttaName = (element['sutta_name'] as String?) ?? 'n/a';

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
}
