/// Turns text selected in the reader into Markdown or HTML, for pasting into
/// a forum post, a document or an email with its shape kept: its headings and
/// paragraphs, each Pāḷi sentence on a line of its own with its translation
/// under it, the bold of paragraph numbers and terms, and the book and page
/// it came from. The Pāḷi is bold when the reader shows it bold.
///
/// A selection gives only its text. Its shape is found by laying that text
/// against the blocks the reader drew, as HTML. The two are compared without
/// their spaces and line breaks, which the drawing and the HTML do not keep
/// alike, so that the first character selected and the last can be found in
/// the HTML and everything between read from there.
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// [plain] is the text alone, in its lines and paragraphs, with no source.
enum CopyFormat { markdown, html, plain }

/// A block as the reader drew it.
class ShownBlock {
  const ShownBlock(this.pageNumber, this.html, {this.paraId});
  final int pageNumber;
  final String html;

  /// ePitaka's paragraph the block begins in, from its first sentence;
  /// null for a page from the old page data.
  final int? paraId;
}

enum _Kind { pali, translation, heading, pageNumber }

/// A run of text with one style.
class _Atom {
  _Atom(this.text, this.kind, this.bold, this.level);
  final String text;
  final _Kind kind;
  final bool bold;
  final int level; // of a heading
  int block = 0;
}

/// Where a line ends, or a paragraph.
class _Break {
  const _Break(this.paragraph);
  final bool paragraph;
}

class FormattedCopy {
  FormattedCopy._();

  static const _translationClasses = {
    'translation_text',
    'english_text',
    'vietnamese_text',
  };
  static const _boldClasses = {'bld', 't5', 'paranum'};
  static const _headingLevels = {
    'book': 1,
    'heading1': 1,
    'chapter': 2,
    'nikaya': 2,
    'heading2': 2,
    't2': 2,
    't3': 2,
    'th31': 2,
    'subhead': 3,
    'subsubhead': 3,
    'heading3': 3,
    'title': 3,
    'heading0': 3,
    'heading4': 4,
    'heading5': 4,
    'heading6': 4,
    'heading7': 4,
  };
  static final _space = RegExp(r'\s+');
  static final _notText = RegExp('[\\s￼\u0001\u0002]');

  /// [selected] laid out in [format], with the source under it: [source]
  /// (the book's name, or the headings it is under) and the page, linked to [link] when there is one.
  /// Null when [selected] is not found in [blocks], in their order on the
  /// page, leaving out text in spans of any of [hiddenClasses]. The Pāḷi is
  /// bold when [paliBold].
  static ({String text, int pageNumber, ShownBlock block})? format(
    String selected,
    List<ShownBlock> blocks,
    CopyFormat format, {
    Set<String> hiddenClasses = const {},
    bool paliBold = false,
    String? source,
    String Function(int pageNumber)? link,
  }) {
    final items = <Object>[];
    for (var i = 0; i < blocks.length; i++) {
      final start = items.length;
      _read(html_parser.parseFragment(blocks[i].html), items, hiddenClasses,
          _Kind.pali, false, 0);
      items.add(const _Break(true));
      for (final item in items.skip(start)) {
        if (item is _Atom) item.block = i;
      }
      if (i > 0 &&
          blocks[i].pageNumber != blocks[i - 1].pageNumber &&
          _continued.hasMatch(blocks[i].html)) {
        _join(items, start);
      }
    }

    // Every character of text, as the item and the place in it.
    final chars = StringBuffer();
    final where = <(int, int)>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is! _Atom) continue;
      for (var c = 0; c < item.text.length; c++) {
        if (_notText.hasMatch(item.text[c])) continue;
        chars.write(item.text[c]);
        where.add((i, c));
      }
    }
    final wanted = selected.replaceAll(_notText, '');
    if (wanted.isEmpty) return null;
    final at = chars.toString().indexOf(wanted);
    if (at < 0) return null;
    final (firstItem, firstChar) = where[at];
    final (lastItem, lastChar) = where[at + wanted.length - 1];

    // The paragraphs selected, each a list of lines, each a list of atoms.
    final paragraphs = <List<List<_Atom>>>[
      [[]]
    ];
    for (var i = firstItem; i <= lastItem; i++) {
      final item = items[i];
      if (item is _Break) {
        if (item.paragraph) {
          if (paragraphs.last.any((l) => l.isNotEmpty)) paragraphs.add([[]]);
        } else if (paragraphs.last.last.isNotEmpty) {
          paragraphs.last.add([]);
        }
        continue;
      }
      final atom = item as _Atom;
      if (atom.kind == _Kind.pageNumber) continue;
      final from = i == firstItem ? firstChar : 0;
      final to = i == lastItem ? lastChar + 1 : atom.text.length;
      final text = atom.text.substring(from, to);
      final line = paragraphs.last.last;
      // A heading, or a change between Pāḷi and translation, starts a line.
      if (line.isNotEmpty &&
          (line.last.kind != atom.kind || atom.kind == _Kind.heading) &&
          text.trim().isNotEmpty) {
        paragraphs.last.add([]);
      }
      paragraphs.last.last.add(
          _Atom(text, atom.kind, atom.bold, atom.level)..block = atom.block);
    }

    final firstAtom = items[firstItem] as _Atom;
    final block = blocks[firstAtom.block];
    final pageNumber = block.pageNumber;
    final body = switch (format) {
      CopyFormat.markdown => _markdown(paragraphs, paliBold),
      CopyFormat.html => _html(paragraphs, paliBold),
      CopyFormat.plain => _plain(paragraphs),
    };
    if (source == null || format == CopyFormat.plain) {
      return (text: body, pageNumber: pageNumber, block: block);
    }
    final cite = '$source, p. $pageNumber';
    final url = link?.call(pageNumber);
    final citation = switch (format) {
      CopyFormat.markdown =>
        url == null ? '— ${_escapeMd(cite)}' : '— [${_escapeMd(cite)}]($url)',
      CopyFormat.html => url == null
          ? '<p>— ${_escapeHtml(cite)}</p>'
          : '<p>— <a href="${_escapeHtml(url)}">${_escapeHtml(cite)}</a></p>',
      CopyFormat.plain => '— $cite', // not reached: plain has no source
    };
    final gap = format == CopyFormat.markdown ? '\n\n' : '\n';
    return (text: '$body$gap$citation', pageNumber: pageNumber, block: block);
  }

  /// A page that begins mid-sentence opens with a paragraph carried on
  /// from the page before.
  static final _continued = RegExp(
      r'^\s*(?:<p[^>]*text-align:right[^>]*>.*?</p>\s*)?<p class="noindentbodytext"',
      dotAll: true);

  /// Joins the block that starts at [start] in [items] to the text before
  /// it, as one paragraph: the sentence the page break cut in two is copied
  /// whole. The breaks between are taken out and a space put in; the page's
  /// number, which is drawn there, is kept to be matched and then left out.
  static void _join(List<Object> items, int start) {
    var from = start;
    while (from > 0 && items[from - 1] is _Break) {
      from--;
    }
    var to = start;
    while (to < items.length) {
      final item = items[to];
      if (item is _Break) {
        to++;
      } else if (item is _Atom &&
          (item.kind == _Kind.pageNumber || item.text.trim().isEmpty)) {
        to++;
      } else {
        break;
      }
    }
    if (from == 0 || to == items.length) return;
    final before = items[from - 1] as _Atom;
    final kept = items
        .sublist(from, to)
        .whereType<_Atom>()
        .where((a) => a.kind == _Kind.pageNumber)
        .toList();
    items.replaceRange(from, to, [
      ...kept,
      _Atom(' ', before.kind, before.bold, before.level)..block = before.block,
    ]);
  }

  /// The text and breaks of [node], in order, into [out].
  static void _read(dom.Node node, List<Object> out, Set<String> hidden,
      _Kind kind, bool bold, int level) {
    if (node is dom.Text) {
      final text = node.text.replaceAll(_space, ' ');
      if (text.isNotEmpty) out.add(_Atom(text, kind, bold, level));
      return;
    }
    if (node is dom.Element) {
      final tag = node.localName;
      final classes = node.classes;
      if (tag == 'script' || tag == 'style') return;
      if (classes.any(hidden.contains)) return;
      // A bookmark is drawn as an icon, not as its text.
      if (tag == 'a' && classes.contains('bookmark')) return;
      if (tag == 'br') {
        out.add(const _Break(false));
        return;
      }
      if (tag == 'span' && classes.contains('linebreak')) {
        out.add(const _Break(true));
        return;
      }
      final style = node.attributes['style'] ?? '';
      if (style.contains('display:none') || style.contains('display: none')) {
        return;
      }
      if (style.contains('text-align:right') && style.contains('brown')) {
        kind = _Kind.pageNumber;
      } else if (classes.any(_translationClasses.contains)) {
        kind = _Kind.translation;
      } else {
        for (final c in classes) {
          final l = _headingLevels[c];
          if (l != null) {
            kind = _Kind.heading;
            level = l;
          }
        }
        if (RegExp(r'^h[1-6]$').hasMatch(tag ?? '')) {
          kind = _Kind.heading;
          level = int.parse(tag!.substring(1));
        }
      }
      if (tag == 'b' || tag == 'strong' || classes.any(_boldClasses.contains)) {
        bold = true;
      }
      final block =
          tag == 'p' || tag == 'div' || (tag?.startsWith('h') ?? false);
      if (block) out.add(const _Break(true));
      for (final child in node.nodes) {
        _read(child, out, hidden, kind, bold, level);
      }
      if (block) out.add(const _Break(true));
      return;
    }
    for (final child in node.nodes) {
      _read(child, out, hidden, kind, bold, level);
    }
  }

  /// Lines of a paragraph end in two spaces, Markdown's mark for a line
  /// break; without them the lines ran together into one.
  static String _markdown(List<List<List<_Atom>>> paragraphs, bool paliBold) {
    final out = <String>[];
    for (final paragraph in paragraphs) {
      final lines = <String>[];
      for (final line in paragraph) {
        if (line.isEmpty) continue;
        final kind = line.first.kind;
        // A line all bold is marked once, not in pieces.
        final wholeBold = paliBold && kind == _Kind.pali;
        var text = _runs(line, (t, bold) {
          final escaped = _escapeMd(t);
          return bold && kind != _Kind.heading && !wholeBold
              ? '**$escaped**'
              : escaped;
        }).trim();
        if (text.isEmpty) continue;
        if (kind == _Kind.heading) {
          text = '${'#' * (line.first.level + 1).clamp(2, 4)} $text';
        } else if (wholeBold) {
          text = '**$text**';
        } else {
          // "1." at the head of a line would make a numbered list.
          text = text.replaceFirstMapped(
              RegExp(r'^(\d+)([.)])'), (m) => '${m[1]}\\${m[2]}');
        }
        lines.add(text);
      }
      if (lines.isEmpty) continue;
      // A heading is a paragraph of its own.
      final buffer = <String>[];
      for (final line in lines) {
        if (line.startsWith('#')) {
          if (buffer.isNotEmpty) out.add(buffer.join('  \n'));
          buffer.clear();
          out.add(line);
        } else {
          buffer.add(line);
        }
      }
      if (buffer.isNotEmpty) out.add(buffer.join('  \n'));
    }
    return out.join('\n\n');
  }

  static String _plain(List<List<List<_Atom>>> paragraphs) => paragraphs
      .map((paragraph) => paragraph
          .where((line) => line.isNotEmpty)
          .map((line) => _runs(line, (t, _) => t).trim())
          .where((line) => line.isNotEmpty)
          .join('\n'))
      .where((p) => p.isNotEmpty)
      .join('\n\n');

  static String _html(List<List<List<_Atom>>> paragraphs, bool paliBold) {
    final out = <String>[];
    for (final paragraph in paragraphs) {
      final lines = <String>[];
      void flush() {
        if (lines.isNotEmpty) out.add('<p>${lines.join('<br>\n')}</p>');
        lines.clear();
      }

      for (final line in paragraph) {
        if (line.isEmpty) continue;
        final kind = line.first.kind;
        final wholeBold = paliBold && kind == _Kind.pali;
        final text = _runs(line, (t, bold) {
          final escaped = _escapeHtml(t);
          return bold && kind != _Kind.heading && !wholeBold
              ? '<b>$escaped</b>'
              : escaped;
        }).trim();
        if (text.isEmpty) continue;
        if (kind == _Kind.heading) {
          flush();
          final h = (line.first.level + 1).clamp(2, 4);
          out.add('<h$h>$text</h$h>');
        } else {
          lines.add(wholeBold ? '<b>$text</b>' : text);
        }
      }
      flush();
    }
    return out.join('\n');
  }

  /// The atoms of [line] as one string, a run of bold text as one piece
  /// with the spaces around it left outside its marks.
  static String _runs(List<_Atom> line, String Function(String, bool) mark) {
    final out = StringBuffer();
    var i = 0;
    while (i < line.length) {
      final bold = line[i].bold;
      final text = StringBuffer();
      while (i < line.length && line[i].bold == bold) {
        text.write(line[i++].text);
      }
      final s = text.toString().replaceAll(_space, ' ');
      final core = s.trim();
      if (core.isEmpty) {
        out.write(s);
        continue;
      }
      if (s.startsWith(' ')) out.write(' ');
      out.write(mark(core, bold));
      if (s.endsWith(' ')) out.write(' ');
    }
    return out.toString().replaceAll(RegExp(' {2,}'), ' ');
  }

  static String _escapeMd(String text) =>
      text.replaceAllMapped(RegExp(r'([\\`*_\[\]<>|])'), (m) => '\\${m[1]}');

  static String _escapeHtml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
