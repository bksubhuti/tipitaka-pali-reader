import 'package:tipitaka_pali/business_logic/models/xray_link.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';

/// Where a commentary link leads, as the reader opens it.
class XrayTarget {
  final String bookId;
  final String bookName;
  final int page;

  const XrayTarget(this.bookId, this.bookName, this.page);
}

/// Reads what the X-ray view shows: the links out of each sentence, the
/// commentary sentence a link points to, and the page it is on.
class XrayRepository {
  final DatabaseHelper databaseProvider;

  XrayRepository(this.databaseProvider);

  static String key(int para, int line) => '$para.$line';

  /// The links out of every sentence of [book] from paragraph [fromPara] to
  /// [toPara], by [key]. Empty when the data is not there.
  Future<Map<String, List<XrayLink>>> linksFor(String book,
      {int? fromPara, int? toPara}) async {
    final db = await databaseProvider.database;
    var where = 'l.src_book = ?';
    final args = <Object?>[book];
    if (fromPara != null) {
      where += ' AND l.src_para >= ?';
      args.add(fromPara);
    }
    if (toPara != null) {
      where += ' AND l.src_para <= ?';
      args.add(toPara);
    }
    final List<Map<String, Object?>> rows;
    try {
      rows = await db.rawQuery(
        'SELECT l.src_para, l.src_line, l.dst_book, l.dst_para, l.dst_line, '
        '  s.pali '
        'FROM epi.book_links l '
        'JOIN epi.sentences s ON s.book_id = l.dst_book '
        '  AND s.para_id = l.dst_para AND s.line_id = l.dst_line '
        'WHERE $where '
        'ORDER BY l.src_para, l.src_line, l.dst_book, l.dst_para, l.dst_line',
        args,
      );
    } catch (_) {
      return const {};
    }
    final out = <String, List<XrayLink>>{};
    for (final row in rows) {
      final word = termOf(row['pali'] as String? ?? '');
      if (word.isEmpty) continue;
      final links = out.putIfAbsent(
          key(row['src_para'] as int, row['src_line'] as int), () => []);
      // The same term linked to two lines of one commentary passage shows
      // once; the first line is where the comment begins.
      if (links.any((l) => l.word == word && l.book == row['dst_book'])) {
        continue;
      }
      links.add(XrayLink(
        word: word,
        book: row['dst_book'] as String,
        para: row['dst_para'] as int,
        line: row['dst_line'] as int,
      ));
    }
    return out;
  }

  static final _bold = RegExp(r'<b>(.*?)</b>');
  static final _edges = RegExp(r'''^[\s‘’“”'",.;:–—-]+|[\s‘’“”'",.;:–—-]+$''');

  /// The term a commentary sentence takes up: what it opens with in bold,
  /// in lower case,
  /// as in `<b>Nandivisālo nāmā</b>ti …`. The download leaves out the word
  /// ePitaka records with each link, and the bold is where it comes from.
  static String termOf(String pali) {
    final match = _bold.firstMatch(pali);
    if (match == null) return '';
    final term = match
        .group(1)!
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(_edges, '')
        .toLowerCase();
    // Before `ti` a closing ṃ is written n: `<b>Evan</b>ti` is evaṃ.
    return term.endsWith('n') ? '${term.substring(0, term.length - 1)}ṃ' : term;
  }

  /// The commentary sentence [link] points to, with its bold intact.
  Future<String?> sentenceOf(XrayLink link) async {
    final db = await databaseProvider.database;
    final rows = await db.rawQuery(
      'SELECT pali FROM epi.sentences '
      'WHERE book_id = ? AND para_id = ? AND line_id = ?',
      [link.book, link.para, link.line],
    );
    if (rows.isEmpty) return null;
    return (rows.first['pali'] as String?)
        ?.replaceAll(RegExp(r'<(?!/?b>)[^>]*>'), '')
        .trim();
  }

  /// The translations of [link]'s sentence in [languages], by language
  /// code. A language without one is left out.
  Future<Map<String, String>> translationsOf(
      XrayLink link, List<String> languages) async {
    final db = await databaseProvider.database;
    final out = <String, String>{};
    for (final code in languages) {
      try {
        final rows = await db.rawQuery(
          'SELECT translation FROM lang_$code.sentences '
          'WHERE book_id = ? AND para_id = ? AND line_id = ?',
          [link.book, link.para, link.line],
        );
        final text = (rows.firstOrNull?['translation'] as String?)?.trim();
        if (text != null && text.isNotEmpty) out[code] = text;
      } catch (_) {
        // A language that will not answer costs that language only.
      }
    }
    return out;
  }

  /// The reader's book and page holding [link]'s sentence, or null when TPR
  /// has no page for it.
  Future<XrayTarget?> targetOf(XrayLink link) async {
    final db = await databaseProvider.database;
    var rows = await db.rawQuery(
      'SELECT b.tpr_book, b.tpr_page, k.name FROM ext.page_break b '
      'JOIN books k ON k.id = b.tpr_book '
      'WHERE b.book_id = ? AND (b.para_id < ? '
      '  OR (b.para_id = ? AND b.line_id <= ?)) '
      'ORDER BY b.para_id DESC, b.line_id DESC LIMIT 1',
      [link.book, link.para, link.para, link.line],
    );
    // Before the book's first break, the opening its first page shows.
    if (rows.isEmpty) {
      rows = await db.rawQuery(
        'SELECT b.tpr_book, b.tpr_page, k.name FROM ext.page_break b '
        'JOIN books k ON k.id = b.tpr_book '
        'WHERE b.book_id = ? ORDER BY b.para_id, b.line_id LIMIT 1',
        [link.book],
      );
    }
    if (rows.isEmpty) return null;
    final row = rows.first;
    return XrayTarget(row['tpr_book'] as String, row['name'] as String,
        row['tpr_page'] as int);
  }
}
