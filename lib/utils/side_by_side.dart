/// Lays a bilingual block out as two columns: each sentence's Pāḷi on the
/// left and its translation on the right, level with each other.
///
/// The page composer writes a sentence as its Pāḷi, a line break and its
/// translations, one after another in a paragraph. Side by side, the
/// paragraph becomes rows, one per sentence, so a long sentence pushes the
/// next row down on both sides and the two never drift apart. Only one
/// translation is shown, the reader's first; two would leave columns too
/// narrow to read.
///
/// The work is split around the reader's own formatting of a block. Before
/// it, the other translations are taken out ([keepOnly]), so that what is
/// counted and underlined is what is drawn. Just before the sentence
/// markers are removed, which is after every highlight has been put in,
/// the places to cut are marked ([mark]). After it, when the classes have
/// become inline styles, the finished block is cut there ([split]).
library;

class SideBySide {
  SideBySide._();

  /// Separates one sentence's row from the next.
  static const rowBreak = '\u0001';

  /// Separates a sentence's Pāḷi from its translation.
  static const columnBreak = '\u0002';

  static final _translation = RegExp(
      r'<br>\s*<span class="translation_text" lang="([^"]*)">(.*?)</span>',
      dotAll: true);

  /// [html] with every translation but [language]'s taken out.
  static String keepOnly(String html, String language) => html.replaceAllMapped(
      _translation, (m) => m.group(1) == language ? m.group(0)! : '');

  static final _sentenceStart =
      RegExp(r'(?:<br>|\s)?(<a name="s\d+_\d+"></a>)');
  static final _paliThenTranslation =
      RegExp(r'</span>\s*<br>\s*(<span class="translation_text")');

  /// Marks where [html] is to be cut: a row at each sentence, and a column
  /// between a sentence's Pāḷi and its translation. A block without a
  /// translation is left as it is.
  static String mark(String html) {
    if (!html.contains('translation_text') || !html.contains('palitext')) {
      return html;
    }
    return html
        .replaceAllMapped(_sentenceStart, (m) => '$rowBreak${m.group(1)}')
        .replaceAllMapped(
            _paliThenTranslation, (m) => '</span>$columnBreak${m.group(1)}');
  }

  static final _openParagraph = RegExp(r'^\s*<p\b[^>]*>');
  static final _anyTag = RegExp(r'<[^>]*>');

  /// The finished [html] of a block as rows of left and right cells, each a
  /// paragraph of its own; null when it was not marked, or is not the shape
  /// expected, and is to be drawn as it is.
  static List<(String, String)>? split(String html) {
    if (!html.contains(columnBreak)) return null;
    final open = _openParagraph.firstMatch(html);
    if (open == null) return null;
    final openTag = open.group(0)!.trim();
    // Rows after the first carry on the paragraph, so are not indented.
    final carryOnTag = openTag.replaceAll(RegExp(r'text-indent:[^;"]*;?'), '');

    // The block's closing line break is left off: the rows are spaced
    // from the next block by the reader instead.
    var body = html.substring(open.end);
    final end = body.lastIndexOf('<span class="linebreak">');
    if (end >= 0) {
      body = body.substring(0, end);
    } else if (body.trimRight().endsWith('</p>')) {
      body = body.trimRight();
      body = body.substring(0, body.length - 4);
    }

    final rows = <(String, String)>[];
    var carried = '';
    for (final row in body.split(rowBreak)) {
      final at = row.indexOf(columnBreak);
      var left = at < 0 ? row : row.substring(0, at);
      final right = at < 0 ? '' : row.substring(at + 1);
      left = carried + left;
      // What comes before the first sentence, such as a page number badge,
      // goes in with it rather than making a row of its own.
      if (right.isEmpty && !_hasText(left)) {
        carried = left;
        continue;
      }
      carried = '';
      final tag = rows.isEmpty ? openTag : carryOnTag;
      rows.add(('$tag$left</p>', right.isEmpty ? '' : '$carryOnTag$right</p>'));
    }
    if (rows.isEmpty) return null;
    if (carried.isNotEmpty) {
      final (left, right) = rows.removeLast();
      rows.add((left.replaceFirst(RegExp(r'</p>$'), '$carried</p>'), right));
    }
    return rows;
  }

  static bool _hasText(String html) =>
      html.replaceAll(_anyTag, '').replaceAll('&nbsp;', '').trim().isNotEmpty;
}
