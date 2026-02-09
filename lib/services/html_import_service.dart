import 'dart:io';
import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart' as dom;
import 'package:sqflite_common/sqlite_api.dart';
import 'package:path/path.dart' as p;
import 'package:tipitaka_pali/services/database/database_helper.dart';

class HtmlImportService {
  final DatabaseHelper dbService = DatabaseHelper();
  static const int kWordsPerPage = 300;

  Future<void> importHtmlFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return;

    // 1. CLEANING PHASE (Use BeautifulSoup)
    // We stick with BS4 here because it's great at stripping junk.
    final rawContent = await file.readAsString();
    final bs = BeautifulSoup(rawContent);
    _cleanSoup(bs);
    final cleanedHtml = bs.body?.innerHtml ?? bs.toString();

    // 2. PARSING PHASE (Use standard 'html' package)
    // We re-parse the clean HTML so we can access TextNodes (naked text).
    final doc = parse(cleanedHtml);
    final body = doc.body;

    // 3. FLATTEN PHASE
    // This turns nested DIVs into a simple stream of [Heading, Text, Br, Text...]
    // preserving the "naked" English translation text.
    final flatNodes = _flattenNodes(body?.nodes ?? []);

    // 4. DATABASE SETUP
    final db = await dbService.database;
    final bookId = _createBookIdFromFilename(filePath);
    final bookTitle = _formatTitle(p.basenameWithoutExtension(filePath));

    await _clearOldData(db, bookId);
    await _insertBook(db, bookId, bookTitle);

    // 5. PROCESS CONTENT
    int currentPage = 1;
    final StringBuffer pageBuffer = StringBuffer();
    int pageWordCount = 0;

    for (final node in flatNodes) {
      // -- A. TOC DETECTION (Elements Only) --
      if (node.nodeType == dom.Node.ELEMENT_NODE) {
        final element = node as dom.Element;

        if (['h1', 'h2'].contains(element.localName)) {
          // Force new page
          if (pageBuffer.isNotEmpty) {
            await _insertPage(db, bookId, currentPage, pageBuffer.toString());
            currentPage++;
            pageBuffer.clear();
            pageWordCount = 0;
          }

          // Add TOC
          final tocName = element.text.trim();
          if (tocName.isNotEmpty) {
            await _insertToc(db, bookId, tocName, currentPage);
          }
        }
      }

      // -- B. BUFFER CONTENT (Text + Elements) --
      // node.outerHtml handles elements; node.text handles text nodes
      String nodeContent = '';
      int nodeWordCount = 0;

      if (node.nodeType == dom.Node.ELEMENT_NODE) {
        final el = node as dom.Element;
        nodeContent = el.outerHtml;
        nodeWordCount = el.text.split(RegExp(r'\s+')).length;
      } else if (node.nodeType == dom.Node.TEXT_NODE) {
        nodeContent = node.text ?? '';
        // Skip purely empty whitespace nodes to save DB space
        if (nodeContent.trim().isEmpty) continue;
        nodeWordCount = nodeContent.split(RegExp(r'\s+')).length;
      }

      // -- C. PAGE BREAK CHECK --
      if (pageWordCount + nodeWordCount > kWordsPerPage &&
          pageBuffer.isNotEmpty) {
        await _insertPage(db, bookId, currentPage, pageBuffer.toString());
        currentPage++;
        pageBuffer.clear();
        pageWordCount = 0;
      }

      pageBuffer.writeln(nodeContent);
      pageWordCount += nodeWordCount;
    }

    // Final flush
    if (pageBuffer.isNotEmpty) {
      await _insertPage(db, bookId, currentPage, pageBuffer.toString());
    }

    await _finalizeBook(db, bookId, currentPage);
  }

  /// Recursively extracts nodes from "Wrapper Divs" but keeps everything else flat.
  List<dom.Node> _flattenNodes(List<dom.Node> nodes) {
    List<dom.Node> flattened = [];

    for (final node in nodes) {
      if (node.nodeType == dom.Node.ELEMENT_NODE) {
        final element = node as dom.Element;

        // CHECK: Is this a wrapper div?
        // Logic: It's a DIV and has Headings inside it.
        bool isWrapper = element.localName == 'div' &&
            (element.querySelector('h1') != null ||
                element.querySelector('h2') != null);

        if (isWrapper) {
          // RECURSE: Don't add the div itself; add its children.
          flattened.addAll(_flattenNodes(element.nodes));
        } else {
          // Keep normal elements (p, h1, b, etc.)
          flattened.add(node);
        }
      } else {
        // Keep Text Nodes (The English Translation!)
        flattened.add(node);
      }
    }
    return flattened;
  }

  void _cleanSoup(BeautifulSoup bs) {
    final unwantedTags = [
      'script',
      'style',
      'meta',
      'link',
      'head',
      'title',
      'noscript'
    ];
    for (var tag in bs.findAll('*')) {
      if (unwantedTags.contains(tag.name)) {
        tag.extract();
      } else {
        tag.attributes.clear(); // Strip styles/classes
        // Normalize tags
        if (tag.name == 'strong') tag.name = 'b';
        if (tag.name == 'em') tag.name = 'i';
        if (tag.name == 'center') tag.name = 'div';
      }
    }
  }

  // --- Database Helpers (Unchanged) ---
  Future<void> _clearOldData(Database db, String bookId) async {
    await db.transaction((txn) async {
      await txn.delete('pages', where: 'bookid = ?', whereArgs: [bookId]);
      await txn.delete('tocs', where: 'book_id = ?', whereArgs: [bookId]);
      await txn.delete('books', where: 'id = ?', whereArgs: [bookId]);
    });
  }

  Future<void> _insertBook(Database db, String bookId, String title) async {
    await db.insert(
        'category', {'id': 'annya_ebook', 'name': 'Ebooks', 'basket': 'annya'},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert(
        'books',
        {
          'id': bookId,
          'name': title,
          'category': 'annya_ebook',
          'basket': 'annya',
          'firstpage': 1
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _insertPage(
      Database db, String bookId, int pageNumber, String content) async {
    await db.insert('pages', {
      'bookid': bookId,
      'page': pageNumber,
      'content': content,
      'paranum': ''
    });
  }

  Future<void> _insertToc(
      Database db, String bookId, String name, int pageNumber) async {
    await db.insert('tocs', {
      'book_id': bookId,
      'name': name,
      'type': 'chapter',
      'page_number': pageNumber
    });
  }

  Future<void> _finalizeBook(Database db, String bookId, int totalPages) async {
    await db.update('books', {'lastPage': totalPages, 'pagecount': totalPages},
        where: 'id = ?', whereArgs: [bookId]);
  }

  String _createBookIdFromFilename(String filepath) {
    final filename = p.basenameWithoutExtension(filepath).toLowerCase();
    return 'ebook_${filename.replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';
  }

  String _formatTitle(String filename) {
    return filename
        .replaceAll('_', ' ')
        .split(' ')
        .map((str) =>
            str.isNotEmpty ? '${str[0].toUpperCase()}${str.substring(1)}' : str)
        .join(' ');
  }
}
