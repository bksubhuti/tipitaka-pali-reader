/// Any HTML tag, opening or closing.
final anyHtmlTag = RegExp(r'<[^>]*>');

/// Applies [transform] to the text of [html] and never to its tags.
///
/// Highlighting used to replace words across the raw markup. A word that also
/// occurs inside a tag — `name` in `<a name="para59">`, `text` in `palitext` —
/// split the tag open, and the page then showed its own HTML as text. Old
/// bookmarks, which highlight every word of a saved passage, hit this most.
///
/// [transform] is also told whether the text already sits inside a span whose
/// tag mentions [highlightClass], so a match there can be left alone.
String mapHtmlText(String html, String highlightClass,
    String Function(String text, bool insideHighlight) transform) {
  final out = StringBuffer();
  final spans = <bool>[];
  var at = 0;
  for (final tag in anyHtmlTag.allMatches(html)) {
    if (tag.start > at) {
      out.write(transform(html.substring(at, tag.start), spans.contains(true)));
    }
    final markup = tag.group(0)!;
    if (markup.startsWith('<span')) {
      spans.add(markup.contains(highlightClass));
    } else if (markup.startsWith('</span') && spans.isNotEmpty) {
      spans.removeLast();
    }
    out.write(markup);
    at = tag.end;
  }
  if (at < html.length) {
    out.write(transform(html.substring(at), spans.contains(true)));
  }
  return out.toString();
}
