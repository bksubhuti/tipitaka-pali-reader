import 'package:flutter_test/flutter_test.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/utils/search_highlight.dart';

String _mark(String html, String term, {int? current, Set<String>? hidden}) =>
    SearchHighlight.highlight(html, term,
        current: current,
        cssClass: 'hit',
        currentCssClass: 'now',
        anchorCssClass: 'go',
        hiddenClasses: hidden ?? const {});

void main() {
  test('marks every match and the current one', () {
    expect(_mark('<p>evaṃ me, evaṃ me</p>', 'evaṃ', current: 2),
        '<p><span class="hit">evaṃ</span> me, <a class="go"></a><span class="now">evaṃ</span> me</p>');
  });

  test('ignores case and leaves the tags alone', () {
    expect(_mark('<span class="palitext">Text text</span>', 'text'),
        '<span class="palitext"><span class="hit">Text</span> <span class="hit">text</span></span>');
  });

  test('a match over a word already highlighted is marked on both sides', () {
    const html = '<p>ekaṃ <span class="highlighted">samayaṃ</span> bhagavā</p>';
    expect(SearchHighlight.count(html, 'ekaṃ samayaṃ'), 1);
    expect(_mark(html, 'ekaṃ samayaṃ', current: 1),
        '<p><a class="go"></a><span class="now">ekaṃ </span><span class="highlighted"><span class="now">samayaṃ</span></span> bhagavā</p>');
  });

  test('a match over a sentence marker is found', () {
    const html = '<p>me sutaṃ <a name="s1_2"></a>ekaṃ samayaṃ</p>';
    expect(SearchHighlight.count(html, 'sutaṃ ekaṃ'), 1);
  });

  test('count agrees with what is drawn once other marks are in', () {
    const stored = '<p><a name="s1_1"></a>evaṃ me sutaṃ <a name="s1_2"></a>'
        'evaṃ me sutaṃ<br><span class="translation_text" lang="en">'
        'Thus have I heard</span></p>';
    const drawn = '<p>evaṃ <span class="underlined_highlight">me</span> sutaṃ '
        '<span class="tts_highlighted">evaṃ me</span> sutaṃ<br>'
        '<span class="translation_text" lang="en">Thus have I heard</span></p>';
    expect(SearchHighlight.count(stored, 'evaṃ me sutaṃ'), 2);
    final marked = _mark(drawn, 'evaṃ me sutaṃ', current: 2);
    expect('<a class="go"></a>'.allMatches(marked).length, 1);
    expect(
        marked, contains('<a class="go"></a><span class="now">evaṃ me</span>'));
  });

  test('a line break between words reads as a space', () {
    expect(
        SearchHighlight.count('<p>bhagavā.<br>Thus</p>', 'bhagavā. Thus'), 1);
    expect(
        SearchHighlight.count('<p>bhagavā.<br>Thus</p>', 'bhagavā.\nThus'), 1);
  });

  test('text not shown is not counted', () {
    const html = '<p><span class="palitext">dhamma</span><br>'
        '<span class="translation_text" lang="en">dhamma <b>x</b></span></p>';
    final hidden = SearchHighlight.hiddenIn(TextDisplayMode.paliOnly);
    expect(SearchHighlight.count(html, 'dhamma'), 2);
    expect(SearchHighlight.count(html, 'dhamma', hiddenClasses: hidden), 1);
    expect(
        _mark(html, 'dhamma', hidden: hidden),
        '<p><span class="palitext"><span class="hit">dhamma</span></span><br>'
        '<span class="translation_text" lang="en">dhamma <b>x</b></span></p>');
  });

  test('an entity is never cut', () {
    expect(_mark('<p>a&nbsp;b</p>', 'nbsp'), '<p>a&nbsp;b</p>');
  });

  test('nothing to look for', () {
    expect(_mark('<p>abc</p>', '  '), '<p>abc</p>');
    expect(SearchHighlight.count('<p>abc</p>', ''), 0);
  });
}
