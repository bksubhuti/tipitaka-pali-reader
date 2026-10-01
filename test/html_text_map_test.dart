import 'package:flutter_test/flutter_test.dart';

import 'package:tipitaka_pali/business_logic/view_models/bookmark_page_view_model.dart';
import 'package:tipitaka_pali/utils/html_text_map.dart';

/// Highlighting changes the text of a page, never its tags.
///
/// The case that broke: an old bookmark highlights every word of its saved
/// passage, and a word that also occurs inside the markup split a tag open,
/// so the page rendered its own HTML as text.
void main() {
  const page = '<p class="bodytext"><a name="para59"></a>'
      '<span class="palitext">59. ekaṃ samayaṃ bhagavā bārāṇasiyaṃ viharati '
      'isipatane migadāye.</span><br><span class="translation_text">59. On one '
      'occasion the Blessed One was dwelling at Benares.</span></p>';

  String mark(String html, String word) => mapHtmlText(
      html,
      'highlighted',
      (text, inside) => inside
          ? text
          : text.replaceAll(word, '<span class="highlighted">$word</span>'));

  test('words that also occur in tags leave the tags whole', () {
    var html = page;
    for (final word in ['name', 'text', 'class', 'span', 'translation']) {
      html = mark(html, word);
    }
    // Every tag of the original is still there, unchanged.
    for (final tag in anyHtmlTag.allMatches(page)) {
      expect(html, contains(tag.group(0)), reason: tag.group(0));
    }
  });

  test('words in the text are marked', () {
    final html = mark(page, 'bhagavā');
    expect(html,
        contains('<span class="highlighted">bhagavā</span> bārāṇasiyaṃ'));
  });

  test('text already inside a highlight is left alone', () {
    final once = mark(page, 'Benares');
    final twice = mark(once, 'Benares');
    expect(twice, once);
  });

  test('a bookmark with nothing worth highlighting highlights nothing', () {
    // Searching for "" would match between every character of the page.
    expect(BookmarkPageViewModel.highlightTextOf(''), isNull);
    expect(BookmarkPageViewModel.highlightTextOf(null), isNull);
    expect(BookmarkPageViewModel.highlightTextOf('7. ti ca me 59'), isNull);
    expect(BookmarkPageViewModel.highlightTextOf('59. ekaṃ samayaṃ bhagavā'),
        'ekaṃ samayaṃ bhagavā');
  });
}
