import 'package:flutter/material.dart';

import '../../business_logic/models/book.dart';
import '../../business_logic/models/search_result.dart';
import '../../data/constants.dart';
import '../../ui/screens/home/search_page/search_page.dart';
import '../database/database_helper.dart';

abstract class FtsRespository {
  Future<List<SearchResult>> getResults(
      String phrase, QueryMode queryMode, int wordDistance,
      {bool isTranslationSearch = false, bool joinEnglish = true});
}

class FtsDatabaseRepository implements FtsRespository {
  final DatabaseHelper databaseHelper;

  FtsDatabaseRepository(this.databaseHelper);

  @override
  Future<List<SearchResult>> getResults(
      String phrase, QueryMode queryMode, int wordDistance,
      {bool isTranslationSearch = false, bool joinEnglish = true}) async {
    if (isTranslationSearch) {
      return await _querySingleTable(phrase, queryMode, wordDistance,
          isTranslation: true);
    }

    // 1. Search Pali table (fts_pages) with parallel translation LEFT JOIN
    final paliResults = await _querySingleTable(phrase, queryMode, wordDistance,
        isTranslation: false);
    if (paliResults.isNotEmpty) {
      return paliResults;
    }

    // 2. Fallback to translation table (fts_translation_pages) if no Pali matches
    return await _querySingleTable(phrase, queryMode, wordDistance,
        isTranslation: true);
  }

  Future<List<SearchResult>> _querySingleTable(
      String phrase, QueryMode queryMode, int wordDistance,
      {required bool isTranslation}) async {
    final results = <SearchResult>[];

    final ftsTable = isTranslation ? 'fts_translation_pages' : 'fts_pages';

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
      SELECT $ftsTable.id, $ftsTable.bookid, books.name, $ftsTable.page, $ftsTable.content, $ftsTable.sutta_name
      FROM $ftsTable INNER JOIN books ON $ftsTable.bookid = books.id
        LEFT JOIN sutta_page_shortcut
            ON $ftsTable.bookid = sutta_page_shortcut.book_id
            AND $ftsTable.page BETWEEN sutta_page_shortcut.start_page AND sutta_page_shortcut.end_page
      WHERE $ftsTable MATCH '"$safePhrase"' AND $ftsTable.content LIKE '%$originalPhrase%'
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
      final pageNumber = element['page'] as int;
      var content = element['content'] as String;
      final suttaName = (element['sutta_name'] as String?) ?? 'n/a';

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
          'SELECT rowid AS id, content FROM fts_translation_pages WHERE rowid IN ($ids)');

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

  RegExp _createExactMatch(String phrase) {
    return RegExp(
      '<$highlightTagName>${RegExp.escape(phrase)}</$highlightTagName>',
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
        RegExp(RegExp.escape(phrase), caseSensitive: false),
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
