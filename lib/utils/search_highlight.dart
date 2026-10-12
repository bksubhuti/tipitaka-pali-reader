/// Finds and marks a find-in-book term in a block of the reader's HTML.
///
/// The matches are counted by the reader's controller on the block as it is
/// stored, and drawn by the page on the block as it is formatted, with other
/// highlights already in it. Both go through here, so that the third match
/// counted is the third match drawn.
///
/// A term is looked for in the text of the block, read across its tags. The
/// drawing used to look in one piece of text at a time, so a match that ran
/// over a tag was not drawn: a word already highlighted from a bookmark or a
/// search result, the word underlined for the dictionary, the sentence being
/// read aloud, a sentence or page marker. The count, made on the stored block,
/// still had it, so every match after it was drawn one place off and the
/// current one fell on the wrong words or on none.
library;

import 'package:tipitaka_pali/services/prefs.dart';

class SearchHighlight {
  SearchHighlight._();

  /// The classes of the text not shown in [mode]: the translations when
  /// only the Pāḷi is shown, the Pāḷi when only a translation is. A match
  /// there would be counted and never seen.
  static Set<String> hiddenIn(TextDisplayMode mode) => switch (mode) {
        TextDisplayMode.paliOnly => const {
            'translation_text',
            'english_text',
            'vietnamese_text'
          },
        TextDisplayMode.translationOnly => const {'palitext'},
        TextDisplayMode.paliAndTranslation => const {},
      };

  static final _tag = RegExp(r'<[^>]*>|&[#a-zA-Z0-9]+;');
  static final _breaking =
      RegExp(r'^</?(?:br|p|div|li|tr|td|h\d)\b', caseSensitive: false);
  static final _classOf = RegExp(r'''class\s*=\s*["']([^"']*)["']''');

  /// How many times [term] is in the text of [html], leaving out the text of
  /// spans with any of [hiddenClasses].
  static int count(String html, String term,
      {Set<String> hiddenClasses = const {}}) {
    final pattern = _pattern(term);
    if (pattern == null) return 0;
    return pattern.allMatches(_read(html, hiddenClasses).text).length;
  }

  /// [html] with every match of [term] in a span of [cssClass], and the
  /// [current] one, counted from 1, in [currentCssClass] after an empty
  /// anchor of [anchorCssClass] to scroll to. A match over a tag is marked
  /// in pieces, one on each side of it, so the markup stays whole.
  static String highlight(
    String html,
    String term, {
    int? current,
    required String cssClass,
    required String currentCssClass,
    required String anchorCssClass,
    Set<String> hiddenClasses = const {},
  }) {
    final pattern = _pattern(term);
    if (pattern == null) return html;
    final read = _read(html, hiddenClasses);
    final matches = pattern.allMatches(read.text).toList();
    if (matches.isEmpty) return html;

    final out = StringBuffer();
    var at = 0; // in html
    var m = 0; // the match being marked
    for (final run in read.runs) {
      out.write(html.substring(at, run.html));
      var pos = run.text; // in text
      final end = run.text + run.length;
      while (pos < end) {
        while (m < matches.length && matches[m].end <= pos) {
          m++;
        }
        if (m == matches.length || matches[m].start >= end) {
          out.write(_slice(html, run, pos, end));
          pos = end;
          break;
        }
        final match = matches[m];
        if (match.start > pos) {
          out.write(_slice(html, run, pos, match.start));
          pos = match.start;
        }
        final to = match.end < end ? match.end : end;
        final isCurrent = current != null && m + 1 == current;
        if (isCurrent && pos == match.start) {
          out.write('<a class="$anchorCssClass"></a>');
        }
        out.write('<span class="${isCurrent ? currentCssClass : cssClass}">'
            '${_slice(html, run, pos, to)}</span>');
        pos = to;
      }
      at = run.html + run.length;
    }
    out.write(html.substring(at));
    return out.toString();
  }

  static String _slice(String html, _Run run, int from, int to) =>
      html.substring(run.html + from - run.text, run.html + to - run.text);

  /// The term's words, with any run of space between them matching any run
  /// of space, or the end of a line, in the text.
  static RegExp? _pattern(String term) {
    final words =
        term.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return null;
    return RegExp(words.map(RegExp.escape).join(r'\s+'),
        caseSensitive: false, unicode: true);
  }

  /// The text of [html], and where each run of it is in [html]. A line
  /// break or a paragraph reads as a space, as does an entity, so a match
  /// never ends inside one.
  static ({String text, List<_Run> runs}) _read(
      String html, Set<String> hiddenClasses) {
    final text = StringBuffer();
    final runs = <_Run>[];
    final spans = <bool>[]; // for each open span, whether it is hidden
    var hidden = 0;
    var at = 0;
    void addText(int end) {
      if (end <= at || hidden > 0) return;
      runs.add(_Run(text.length, at, end - at));
      text.write(html.substring(at, end));
    }

    for (final tag in _tag.allMatches(html)) {
      addText(tag.start);
      final markup = tag.group(0)!;
      if (markup.startsWith('&') || _breaking.hasMatch(markup)) {
        if (hidden == 0) text.write(' ');
      } else if (markup.startsWith('<span')) {
        final classes =
            (_classOf.firstMatch(markup)?.group(1) ?? '').split(' ').toSet();
        final hides = classes.any(hiddenClasses.contains);
        spans.add(hides);
        if (hides) hidden++;
      } else if (markup.startsWith('</span') && spans.isNotEmpty) {
        if (spans.removeLast()) hidden--;
      }
      at = tag.end;
    }
    addText(html.length);
    return (text: text.toString(), runs: runs);
  }
}

class _Run {
  const _Run(this.text, this.html, this.length);

  /// Where it starts in the text, and in the HTML.
  final int text, html;
  final int length;
}
