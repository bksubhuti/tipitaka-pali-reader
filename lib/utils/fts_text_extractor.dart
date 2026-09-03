/// FTS Text Extractor
/// Extracts clean Pali and Translation text from HTML content for FTS indexing.
///
/// Handles nested <span> and <p> tags with depth tracking so that inner tags
/// (e.g. <span class="bld"> or <span class="paranum">) do not cause early truncation.
class FtsTextExtractor {
  FtsTextExtractor._();

  static final _spanTagRegex =
      RegExp(r'<span\b[^>]*>|</span\s*>', caseSensitive: false);
  static final _pTagRegex = RegExp(r'<p\b[^>]*>|</p\s*>', caseSensitive: false);
  static final _htmlTagRegex = RegExp(r'<[^>]*>');

  static final _openPaliRegex = RegExp(
    r'<(span|p)\b[^>]*class=["\x27]?[^>"\x27]*\bpalitext\b[^>"\x27]*["\x27]?[^>]*>',
    caseSensitive: false,
  );

  static final _openTransRegex = RegExp(
    r'<(span|p)\b[^>]*class=["\x27]?[^>"\x27]*\btranslation_text\b[^>"\x27]*["\x27]?[^>]*>',
    caseSensitive: false,
  );

  /// Extracts pure Pali text from [html].
  ///
  /// If the HTML contains `palitext` elements (bilingual pages), extracts all
  /// content inside those elements with tag-depth tracking.
  /// If no `palitext` elements are present (standard unilingual books),
  /// extracts the cleaned text of the entire page.
  static String extractPaliText(String html) {
    if (html.contains('palitext')) {
      final paliContent = extractBlockContent(html, _openPaliRegex);
      return cleanText(paliContent);
    }
    return cleanText(html);
  }

  /// Extracts translation text from [html].
  ///
  /// If the HTML contains `translation_text` elements, extracts all content
  /// inside those elements with tag-depth tracking.
  /// Returns empty string if no translation elements are present.
  static String extractTranslationText(String html) {
    if (html.contains('translation_text')) {
      final transContent = extractBlockContent(html, _openTransRegex);
      return cleanText(transContent);
    }
    return '';
  }

  /// Extracts the inner content of all tags matched by [openTagRegex],
  /// properly tracking opening and closing tags of that tag type (span or p)
  /// so that nested inner tags do not prematurely end the match.
  static String extractBlockContent(String html, RegExp openTagRegex) {
    final buffer = StringBuffer();
    int pos = 0;

    while (pos < html.length) {
      final openMatches = openTagRegex.allMatches(html, pos);
      if (openMatches.isEmpty) break;
      final match = openMatches.first;

      final tagType = match.group(1)!.toLowerCase();
      final tagRegex = tagType == 'p' ? _pTagRegex : _spanTagRegex;
      final startContent = match.end;
      int depth = 1;
      int scanPos = startContent;

      while (depth > 0 && scanPos < html.length) {
        final tagMatches = tagRegex.allMatches(html, scanPos);
        if (tagMatches.isEmpty) {
          // Unclosed tag: capture remaining content safely
          buffer.write(' ');
          buffer.write(html.substring(startContent));
          pos = html.length;
          break;
        }

        final tagMatch = tagMatches.first;
        final matchedTag = tagMatch.group(0)!.toLowerCase();

        if (matchedTag.endsWith('/>')) {
          // Self-closing tag, depth is unaffected
        } else if (matchedTag.startsWith('</')) {
          depth--;
          if (depth == 0) {
            buffer.write(' ');
            buffer.write(html.substring(startContent, tagMatch.start));
            pos = tagMatch.end;
            break;
          }
        } else {
          depth++;
        }
        scanPos = tagMatch.end;
      }
    }

    return buffer.toString();
  }

  /// Cleans HTML tags, quotes, and normalizes text for FTS indexing.
  static String cleanText(String text) {
    text = text.replaceAll(_htmlTagRegex, '');
    text = text.replaceAll('"', '');
    text = text.replaceAll("'", '');
    return text.trim();
  }
}
