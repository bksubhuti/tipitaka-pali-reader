import 'package:tipitaka_pali/utils/html_text_map.dart';

/// Finding and marking sentences in a composed page, by the anchors the page
/// composer puts where each sentence begins (`<a name="s12_3"></a>`).
///
/// The earlier attempt at reading aloud found the spoken sentence by
/// searching for its text in the HTML. That broke on anything between the
/// words — a page anchor, a variant reading, another script — and the
/// highlight landed in the wrong place or nowhere. An anchor survives all of
/// those, so nothing here compares text.
class TtsHighlight {
  TtsHighlight._();

  static final _marker = RegExp(r'<a name="(s\d+_\d+)"></a>');
  static final _lang = RegExp(r'lang="([^"]*)"');

  /// The first sentence on [html], or null if it has none.
  static String? firstSentence(String html) =>
      _marker.firstMatch(html)?.group(1);

  /// Marks the part of [sentence] spoken in [language] with [cssClass], and
  /// puts [scrollAnchor] just before it so the reader can bring it into view.
  ///
  /// [language] is 'pali' for the Pali, or a translation's code. Only the
  /// text between tags is wrapped, piece by piece, so the markup stays valid
  /// however the sentence is built.
  static String highlight(
    String html,
    String sentence,
    String language, {
    String cssClass = 'tts_highlighted',
    String scrollAnchor = '<a class="scroll_to_tts"></a>',
  }) {
    final marker = '<a name="$sentence"></a>';
    final start = html.indexOf(marker);
    if (start < 0) return html;
    final from = start + marker.length;

    // The sentence runs to the next sentence or the end of its paragraph.
    var end = html.length;
    for (final stop in ['<a name="s', '</p>', '<p ', '<span class="linebreak"']) {
      final at = html.indexOf(stop, from);
      if (at >= 0 && at < end) end = at;
    }

    final out = StringBuffer(html.substring(0, from));
    // Per open span: the language of a translation, 'note' for a variant
    // reading, null for anything else. Variant readings are not spoken, and a
    // highlight inside one would stop the reader from hiding it.
    final languages = <String?>[];
    var anchored = false;
    var at = from;
    void text(String run) {
      final inside = languages.lastWhere((l) => l != null, orElse: () => null);
      final speaking = inside ?? 'pali';
      if (languages.contains('note')) {
        out.write(run);
        return;
      }
      if (speaking != language || run.trim().isEmpty) {
        out.write(run);
        return;
      }
      if (!anchored) {
        out.write(scrollAnchor);
        anchored = true;
      }
      out.write('<span class="$cssClass">$run</span>');
    }

    final body = html.substring(from, end);
    for (final tag in anyHtmlTag.allMatches(body)) {
      if (tag.start > at - from) text(body.substring(at - from, tag.start));
      final markup = tag.group(0)!;
      if (markup.startsWith('<span')) {
        languages.add(markup.contains('translation_text')
            ? (_lang.firstMatch(markup)?.group(1) ?? '?')
            : markup.contains('"note"')
                ? 'note'
                : null);
      } else if (markup.startsWith('</span') && languages.isNotEmpty) {
        languages.removeLast();
      }
      out.write(markup);
      at = from + tag.end;
    }
    if (at < end) text(html.substring(at, end));
    out.write(html.substring(end));
    return out.toString();
  }

  /// The sentence holding the [occurrence]th appearance (from 0) of [word]
  /// in the text of [html], or the page's first sentence if it cannot tell.
  ///
  /// This is how reading aloud starts where the reader tapped: the tap gives
  /// the word and which occurrence of it on the block, and the sentence is
  /// whichever began last before it.
  static String? sentenceAt(String html, String word, int occurrence) {
    if (word.isEmpty) return firstSentence(html);
    String? current;
    var seen = 0;
    var at = 0;
    for (final tag in anyHtmlTag.allMatches(html)) {
      final found = _count(html.substring(at, tag.start), word);
      if (seen + found > occurrence) return current ?? firstSentence(html);
      seen += found;
      final name = _marker.firstMatch(tag.group(0)! + '</a>')?.group(1);
      if (name != null) current = name;
      at = tag.end;
    }
    return current ?? firstSentence(html);
  }

  static int _count(String text, String word) => word.allMatches(text).length;
}
