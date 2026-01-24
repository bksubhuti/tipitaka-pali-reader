/*import 'dart:io';
import 'package:epubx/epubx.dart';
import 'package:html/parser.dart' show parse, parseFragment;
import 'package:html/dom.dart' as dom;
import 'package:sqflite_common/sqlite_api.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:path/path.dart' as p;

const int kWordsPerPage = 300;

class EpubImportService {
  final DatabaseHelper dbService = DatabaseHelper();

  Future<void> importFile(String epubPath) async {
    final epubBook =
        await EpubReader.readBook(await File(epubPath).readAsBytes());
    final db = await dbService.database;

    final bookId = _createBookIdFromFilename(epubPath);
    final bookTitle = epubBook.Title ?? p.basenameWithoutExtension(epubPath);

    await db.delete('pages', where: 'bookid = ?', whereArgs: [bookId]);
    await db.delete('tocs', where: 'book_id = ?', whereArgs: [bookId]);
    await db.delete('books', where: 'id = ?', whereArgs: [bookId]);

    await db.insert(
      'category',
      {'id': 'annya_ebook', 'name': 'Ebooks', 'basket': 'annya'},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    await _insertBook(db, bookId, bookTitle);

    int pageNumber = 1;

    final chapters = epubBook.Chapters;
    if (chapters != null) {
      for (final chapter in chapters) {
        await insertAll(db, bookId, chapter, pageNumber);

        // Count how many pages this chapter added
        final rawHtml = chapter.HtmlContent ?? '';
        final cleanHtml = parseChapterHtml(rawHtml);
        final pages = splitIntoPages(cleanHtml);
        pageNumber += pages.length;
      }
    }

    final totalPages = pageNumber - 1;
    await db.update(
      'books',
      {
        'firstpage': 1,
        'lastPage': totalPages,
        'pagecount': totalPages,
      },
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Future<void> _insertBook(Database db, String bookId, String title) async {
    await db.insert(
      'books',
      {
        'id': bookId,
        'name': title,
        'category': 'annya_ebook',
        'basket': 'annya',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _insertToc(
      Database db, String bookId, String title, int pageNumber) async {
    await db.insert(
      'tocs',
      {
        'book_id': bookId,
        'name': title,
        'type': 'chapter',
        'page_number': pageNumber,
      },
    );
  }

  Future<void> _insertPage(
      Database db, String bookId, int pageNumber, String content) async {
    await db.insert(
      'pages',
      {
        'bookid': bookId,
        'page': pageNumber,
        'content': content,
        'paranum': '',
      },
    );
  }

  String _createBookIdFromFilename(String filepath) {
    final filename = p.basenameWithoutExtension(filepath).toLowerCase();
    return 'ebook_${filename.replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';
  }

  String _transformHtml(String html) {
    final doc = parse(html);

    // Remove <head>, <script>, <style>
    doc.head?.remove();
    doc.querySelectorAll('script, style').forEach((e) => e.remove());

    final body = doc.body;
    if (body == null) return '';

    // Convert specific class patterns to semantic HTML tags
    final classToTagMap = {
      'chapter-title': 'h1',
      'section-title': 'h2',
      'subtitle': 'h3',
      'centered': 'p',
      'bold': 'b',
      'italic': 'i',
    };

    for (final entry in classToTagMap.entries) {
      final elements = body.querySelectorAll('.${entry.key}');
      for (final el in elements) {
        final newEl = dom.Element.tag(entry.value);
        newEl.innerHtml = el.innerHtml;
        el.replaceWith(newEl);
      }
    }
    // Strip all class, id, style attributes from all elements
    for (final el in body.querySelectorAll('*')) {
      el.attributes.remove('class');
      el.attributes.remove('id');
      el.attributes.remove('style');
    }

    // Normalize <br> spacing
    for (final br in body.querySelectorAll('br')) {
      br.replaceWith(dom.Element.tag('br'));
    }

    return body.innerHtml.trim();
  }

  String parseChapterHtml(String rawHtml) {
    final doc = parse(rawHtml);
    final body = doc.body;

    final classToTagMap = {
      'italic': 'i',
      'bold': 'b',
      'underline': 'u',
      'center': 'center',
      'right': 'div style="text-align: right"',
      'left': 'div style="text-align: left"',
      // Add more as needed
    };

    for (final entry in classToTagMap.entries) {
      final elements = body?.querySelectorAll('.${entry.key}') ?? [];
      for (final el in elements) {
        final newTag = entry.value;
        final newEl = parseFragment('<$newTag>${el.innerHtml}</$newTag>');
        el.replaceWith(newEl);
      }
    }

    return body?.innerHtml.trim() ?? '';
  }

  List<String> splitIntoPages(String htmlContent, {int wordsPerPage = 300}) {
    final doc = parse('<div>$htmlContent</div>');
    final paragraphs = doc.querySelectorAll('p');
    final pages = <String>[];

    var buffer = StringBuffer();
    var wordCount = 0;

    for (final p in paragraphs) {
      final text = p.outerHtml;
      final count = text.split(RegExp(r'\s+')).length;

      if (wordCount + count > wordsPerPage && buffer.isNotEmpty) {
        pages.add(buffer.toString().trim());
        buffer.clear();
        wordCount = 0;
      }

      buffer.writeln(text);
      wordCount += count;
    }

    if (buffer.isNotEmpty) {
      pages.add(buffer.toString().trim());
    }

    return pages;
  }

  Future<void> insertAll(
      Database db, String bookId, EpubChapter chapter, int startPage) async {
    final rawHtml = chapter.HtmlContent ?? '';
    final cleanHtml = parseChapterHtml(rawHtml);
    final pages = splitIntoPages(cleanHtml);

    await db.insert('tocs', {
      'book_id': bookId,
      'name': chapter.Title?.trim() ?? 'Chapter',
      'type': 'chapter',
      'page_number': startPage,
    });

    for (int i = 0; i < pages.length; i++) {
      await db.insert('pages', {
        'bookid': bookId,
        'page': startPage + i,
        'content': pages[i],
        'paranum': '',
      });
    }
  }
}
*/
