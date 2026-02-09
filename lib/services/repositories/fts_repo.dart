import 'package:flutter/material.dart';

import '../../business_logic/models/book.dart';
import '../../business_logic/models/search_result.dart';
import '../../data/constants.dart';
import '../../ui/screens/home/search_page/search_page.dart';
import '../database/database_helper.dart';

abstract class FtsRespository {
  Future<List<SearchResult>> getResults(
      String phrase, QueryMode queryMode, int wordDistance);
}

class FtsDatabaseRepository implements FtsRespository {
  final DatabaseHelper databaseHelper;

  FtsDatabaseRepository(this.databaseHelper);

  @override
  Future<List<SearchResult>> getResults(
      String phrase, QueryMode queryMode, int wordDistance) async {
    final results = <SearchResult>[];

    // 1. SANITIZE INPUT: Prevents SQL Injection crashes (e.g., taṇhā'ti)
    String safePhrase = phrase.replaceAll("'", "''");

    final db = await databaseHelper.database;

    late String sql;

    if (queryMode == QueryMode.exact) {
      // CORRECT: Uses safePhrase and proper single quoting
      sql = '''
      SELECT fts_pages.id, bookid, name, page, content, fts_pages.sutta_name
      FROM fts_pages INNER JOIN books ON fts_pages.bookid = books.id
        LEFT JOIN sutta_page_shortcut
            ON fts_pages.bookid = sutta_page_shortcut.book_id
            AND fts_pages.page BETWEEN sutta_page_shortcut.start_page AND sutta_page_shortcut.end_page
      WHERE fts_pages MATCH '"$safePhrase"'
      ''';
    }

    if (queryMode == QueryMode.prefix) {
      final value = '$safePhrase '.replaceAll(' ', '* ').trim();

      // FIX: Changed from '"$value"' to "'$value'"
      // Standard FTS5 requires single quotes for string literals.
      // Double quotes are for column names.
      sql = '''
      SELECT fts_pages.id, bookid, name, page, content, fts_pages.sutta_name
      FROM fts_pages INNER JOIN books ON fts_pages.bookid = books.id
        LEFT JOIN sutta_page_shortcut
            ON fts_pages.bookid = sutta_page_shortcut.book_id
            AND fts_pages.page BETWEEN sutta_page_shortcut.start_page AND sutta_page_shortcut.end_page
      WHERE fts_pages MATCH '$value'
      ''';
    }

    if (queryMode == QueryMode.distance) {
      // 1. Split input into individual words
      final words = safePhrase.split(' ').where((w) => w.isNotEmpty);

      // 2. Add quotes and wildcards to each word: "word"*
      final formattedWords = words.map((w) => '"$w"*').join(' ');

      // 3. Wrap in the FTS5 NEAR function: NEAR("word1"* "word2"*, distance)
      final value = 'NEAR($formattedWords, $wordDistance)';

      sql = '''
      SELECT fts_pages.id, bookid, name, page, fts_pages.sutta_name,
        SNIPPET(fts_pages, -1, '<$highlightTagName>', '</$highlightTagName>', '...', 25) AS content
      FROM fts_pages 
      INNER JOIN books ON fts_pages.bookid = books.id
      LEFT JOIN sutta_page_shortcut
          ON fts_pages.bookid = sutta_page_shortcut.book_id
          AND fts_pages.page BETWEEN sutta_page_shortcut.start_page AND sutta_page_shortcut.end_page
      WHERE fts_pages MATCH '$value'
      ''';
    }
    if (queryMode == QueryMode.anywhere) {
      // CORRECT: Uses safePhrase
      sql = '''
      SELECT fts_pages.id, bookid, name, page, content, fts_pages.sutta_name
      FROM fts_pages INNER JOIN books ON fts_pages.bookid = books.id
        LEFT JOIN sutta_page_shortcut
            ON fts_pages.bookid = sutta_page_shortcut.book_id
            AND fts_pages.page BETWEEN sutta_page_shortcut.start_page AND sutta_page_shortcut.end_page
      WHERE content LIKE '%$safePhrase%'
      ''';
    }

    var maps = await db.rawQuery(sql);

    // --- Result Parsing ---

    // Optimization: Create regex once (using safe RegExp.escape)
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

      // 1. DISTANCE MODE (Already handled by SNIPPET)
      if (queryMode == QueryMode.distance) {
        results.add(SearchResult(
          id: id,
          book: Book(id: bookId, name: bookName),
          pageNumber: pageNumber,
          description: content, // Snippet provided by SQL
          suttaName: suttaName,
        ));
        continue; // Skip manual processing
      }

      // 2. OTHER MODES (Manual Highlight & Extract)

      // Inject highlight tags (Case Insensitive)
      content = _buildHighlight(content, phrase);

      final matches = regexMatchWords.allMatches(content);

      // If matches found, process them
      if (matches.isNotEmpty) {
        // Loop through matches (or just take the first one if you prefer)
        // Your logic had a mix of "if length == 1" and "else loop".
        // A loop handles both cases cleanly.
        for (var match in matches) {
          final String description =
              _extractDescription(content, match.start, match.end);

          results.add(SearchResult(
            id: id,
            book: Book(id: bookId, name: bookName),
            pageNumber: pageNumber,
            description: description,
            suttaName: suttaName,
          ));

          // NOTE: If you only want 1 result per page, uncomment `break`:
          // break;
        }
      } else if (queryMode == QueryMode.anywhere) {
        // Fallback: If 'anywhere' matched via SQL LIKE but regex failed
        // (e.g. overlap or special chars), return raw content snippet.
        results.add(SearchResult(
          id: id,
          book: Book(id: bookId, name: bookName),
          pageNumber: pageNumber,
          description:
              _getRightHandSideWords(content, 20), // Grab start of text
          suttaName: suttaName,
        ));
      }
    }

    debugPrint('total results:${results.length}');
    return results;
  }

  String _extractDescription(String content, int start, int end) {
    final word = content.substring(start, end);
    const wordCountForDescription = 8;
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
      // FIX: Changed condition from (index - i >= 0) to (index >= 0)
      // The old logic was skipping valid words.
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
    // FIX: Escape input to prevent Regex crash on chars like '(', ')'
    return RegExp(
        '<$highlightTagName>${RegExp.escape(phrase)}</$highlightTagName>');
  }

  RegExp _createPrefixMatch(String phrase) {
    final patterns = <String>[];
    final words = phrase.split(' ');
    for (var word in words) {
      // FIX: Escape input here too
      patterns.add(
          '<$highlightTagName>${RegExp.escape(word)}.*?</$highlightTagName>');
    }
    return RegExp(patterns.join(' '));
  }

  String _buildHighlight(String content, String phrase) {
    // FIX: Use caseSensitive: false
    // This allows "Metta" search to highlight "metta" in text.
    return content.replaceAllMapped(
        RegExp(RegExp.escape(phrase), caseSensitive: false),
        (match) => '<$highlightTagName>${match.group(0)}</$highlightTagName>');
  }
}
