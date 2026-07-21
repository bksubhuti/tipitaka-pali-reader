/// Pali English Stripper
/// Strips English translation text from mixed Pali/English content
/// using the labeled HTML from the pages table.
///
/// The page HTML uses:
///   <span class="palitext">...</span>        for Pali text
///   <span class="translation_text ...">...</span>  for English translations

/// Pre-compiled regex constants for performance
final _paliSpanRegex = RegExp(
  r'<span class="palitext"[^>]*>(.*?)</span>',
  dotAll: true,
  caseSensitive: false,
);

final _nonPaliChars = RegExp(r'[^\wāīūṝḷṃṅñṭḍṇḷṆṬḌṂÑṚĀĪŪṜḶ]');
final _whitespace = RegExp(r'\s+');

/// Strip English from a mixed Pali/English text sample.
///
/// [mixedSample] is the HTML-stripped search result description (mixed text).
/// [labeledPageHtml] is the full HTML content from the pages table for this
/// book+page, which has labeled <span class="palitext"> and
/// <span class="translation_text"> spans.
///
/// If no labeled HTML is available, returns the original text unchanged.
String stripEnglishFromPali({
  required String mixedSample,
  String? labeledPageHtml,
}) {
  if (labeledPageHtml == null || labeledPageHtml.isEmpty) {
    return mixedSample; // No labeled page available, return as-is
  }
  return _stripUsingLabeledPage(mixedSample, labeledPageHtml);
}

/// Build a Pali vocabulary set from the labeled HTML page,
/// then keep only words from the mixed sample that appear in
/// that vocabulary.
String _stripUsingLabeledPage(String sample, String labeledHtml) {
  final paliVocabulary = _extractPaliWordsFromHtml(labeledHtml);

  if (paliVocabulary.isEmpty) {
    return sample; // No palitext spans found, return as-is
  }

  final words = sample.split(_whitespace);
  final result = <String>[];

  for (var word in words) {
    if (word.trim().isEmpty) continue;

    // Clean for comparison (keep original word for output)
    final cleanWord = word.replaceAll(_nonPaliChars, '').toLowerCase();

    if (cleanWord.isNotEmpty && paliVocabulary.contains(cleanWord)) {
      result.add(word);
    }
  }

  return result.join(' ').trim();
}

/// Extract all Pali words from <span class="palitext"> elements
/// in the labeled HTML page.
Set<String> _extractPaliWordsFromHtml(String html) {
  final paliWords = <String>{};

  for (final match in _paliSpanRegex.allMatches(html)) {
    final content = match.group(1) ?? '';
    final words = content.split(_whitespace);

    for (var w in words) {
      final clean = w.replaceAll(_nonPaliChars, '').toLowerCase();

      if (clean.isNotEmpty) {
        paliWords.add(clean);
      }
    }
  }

  return paliWords;
}
