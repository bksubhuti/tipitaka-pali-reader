import 'package:flutter_test/flutter_test.dart';

import 'package:tipitaka_pali/utils/html_text_map.dart';
import 'package:tipitaka_pali/utils/tts_highlight.dart';

/// The spoken sentence is found by its marker, never by its text.
void main() {
  const page = '<p class="bodytext"><a name="s59_1"></a>'
      '<span class="palitext">59. ekaṃ samayaṃ <a name="P1.0055"></a>bhagavā '
      '<span class="note">[bhagavā (ka.)]</span> viharati.</span>'
      '<br><span class="translation_text" lang="en">On one occasion the '
      'Blessed One.</span><br><a name="s59_2"></a><span class="palitext">'
      'tatra kho bhagavā āmantesi.</span><br>'
      '<span class="translation_text" lang="en">There he addressed them.'
      '</span></p>';

  String marked(String html) =>
      RegExp(r'<span class="tts_highlighted">([^<]*)</span>')
          .allMatches(html)
          .map((m) => m.group(1))
          .join('|');

  test('the Pali of a sentence, across the anchors inside it', () {
    final html = TtsHighlight.highlight(page, 's59_1', 'pali');
    // The variant reading is neither spoken nor marked.
    expect(marked(html), '59. ekaṃ samayaṃ |bhagavā | viharati.');
    expect(html, isNot(contains('<span class="tts_highlighted">On one')));
    expect(html, isNot(contains('<span class="tts_highlighted">tatra')));
  });

  test('the translation alone when that is what is spoken', () {
    final html = TtsHighlight.highlight(page, 's59_2', 'en');
    expect(marked(html), 'There he addressed them.');
    expect(html.indexOf('<a class="scroll_to_tts"></a>'),
        lessThan(html.indexOf('There he addressed')));
  });

  test('the markup is untouched apart from what was added', () {
    final html = TtsHighlight.highlight(page, 's59_1', 'pali')
        .replaceAll('<a class="scroll_to_tts"></a>', '')
        .replaceAll('<span class="tts_highlighted">', '')
        .replaceAll(RegExp(r'</span>'), '');
    expect(html, page.replaceAll('</span>', ''));
    for (final tag in anyHtmlTag.allMatches(page)) {
      expect(TtsHighlight.highlight(page, 's59_2', 'en'),
          contains(tag.group(0)));
    }
  });

  test('a sentence not on this block changes nothing', () {
    expect(TtsHighlight.highlight(page, 's60_1', 'pali'), page);
  });

  test('a tap finds its sentence', () {
    expect(TtsHighlight.sentenceAt(page, 'bhagavā', 0), 's59_1');
    // The third bhagavā (after the variant reading's) is in sentence 2.
    expect(TtsHighlight.sentenceAt(page, 'bhagavā', 2), 's59_2');
    expect(TtsHighlight.sentenceAt(page, 'āmantesi', 0), 's59_2');
    expect(TtsHighlight.sentenceAt(page, 'nowhere', 0), 's59_2',
        reason: 'not found: the last sentence seen');
    expect(TtsHighlight.firstSentence(page), 's59_1');
  });
}
