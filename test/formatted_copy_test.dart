import 'package:flutter_test/flutter_test.dart';
import 'package:tipitaka_pali/utils/formatted_copy.dart';
import 'package:tipitaka_pali/utils/page_composer.dart';

/// A block as the reader leaves it before styling: sentence markers gone, a
/// line break widget at the end of each paragraph.
String _drawn(String html) => html
    .replaceAll(PageComposer.sentenceMarkers, '')
    .replaceAll('</p>', '<span class="linebreak"></span><p>');

void main() {
  final para1 = _drawn(PageComposer.compose(const [
    PageSentence(
        paraId: 1,
        lineId: 1,
        pali: '1. Evaṃ me sutaṃ.',
        paraNum: '1',
        translations: ['Thus have I heard.']),
    PageSentence(
        paraId: 1,
        lineId: 2,
        pali: 'Ekaṃ samayaṃ bhagavā.',
        translations: ['At one time the Blessed One.']),
  ], languages: [
    'en'
  ]));
  final para2 = _drawn(PageComposer.compose(const [
    PageSentence(
        paraId: 2,
        lineId: 1,
        pali: 'Tatra kho bhagavā bhikkhū āmantesi.',
        translations: ['There the Blessed One addressed the monks.']),
  ], languages: [
    'en'
  ]));
  const header = '<p style="color:brown;text-align:right;"> 12</p>';
  final blocks = [
    ShownBlock(12, '$header$para1'),
    const ShownBlock(12, '<p class="heading2">Mūlapariyāya</p>'),
    ShownBlock(13, para2),
  ];

  String md(String selected) =>
      FormattedCopy.format(selected, blocks, CopyFormat.markdown)!.text;

  test('Pali and translation on lines of their own, paragraphs apart', () {
    // As a drag across the page gives it: the page number, and lines run
    // together where side by side columns meet.
    const selected = '12\n1. Evaṃ me sutaṃ.\nThus have I heard.Ekaṃ samayaṃ '
        'bhagavā.\nAt one time the Blessed One.\n Mūlapariyāya\nTatra kho';
    expect(
        md(selected),
        '1\\. Evaṃ me sutaṃ.  \n'
        'Thus have I heard.  \n'
        'Ekaṃ samayaṃ bhagavā.  \n'
        'At one time the Blessed One.\n\n'
        '### Mūlapariyāya\n\n'
        'Tatra kho');
  });

  test('a selection inside a sentence keeps only what was selected', () {
    expect(md('me sutaṃ'), 'me sutaṃ');
    expect(md('heard.Ekaṃ'), 'heard.  \nEkaṃ');
  });

  test('the Pali bold when the reader shows it bold', () {
    String bold(String selected, CopyFormat f) =>
        FormattedCopy.format(selected, blocks, f, paliBold: true)!.text;
    expect(bold('1. Evaṃ me sutaṃ. Thus have I heard.', CopyFormat.markdown),
        '**1. Evaṃ me sutaṃ.**  \nThus have I heard.');
    expect(bold('me sutaṃ. Thus', CopyFormat.html),
        '<p><b>me sutaṃ.</b><br>\nThus</p>');
  });

  test('HTML, with the source linked', () {
    final out = FormattedCopy.format(
        'samayaṃ bhagavā. At one time', blocks, CopyFormat.html,
        source: 'Dīgha Nikāya', link: (page) => 'https://x/?p=$page')!;
    expect(out.pageNumber, 12);
    expect(
        out.text,
        '<p>samayaṃ bhagavā.<br>\nAt one time</p>\n'
        '<p>— <a href="https://x/?p=12">Dīgha Nikāya, p. 12</a></p>');
  });

  test('the page is the one the selection starts on', () {
    final out = FormattedCopy.format('Tatra', blocks, CopyFormat.markdown,
        source: 'MN', link: (page) => 'https://x/$page')!;
    expect(out.text, 'Tatra\n\n— [MN, p. 13](https://x/13)');
  });

  test('bold, and what Markdown would read as its own', () {
    final b = [
      const ShownBlock(1,
          '<p class="bodytext"><span class="bld">dhamma</span> is *x* [y]</p>')
    ];
    expect(
        FormattedCopy.format('dhamma is *x* [y]', b, CopyFormat.markdown)!.text,
        r'**dhamma** is \*x\* \[y\]');
    expect(FormattedCopy.format('dhamma is', b, CopyFormat.html)!.text,
        '<p><b>dhamma</b> is</p>');
  });

  test('hidden text is not read, and text not found gives null', () {
    final hidden = {'translation_text'};
    expect(
        FormattedCopy.format('sutaṃ.Ekaṃ', blocks, CopyFormat.markdown,
                hiddenClasses: hidden)!
            .text,
        'sutaṃ.  \nEkaṃ');
    expect(FormattedCopy.format('not here', blocks, CopyFormat.html), isNull);
  });

  group('a sentence cut by a page break', () {
    // The first block of a page carries the page number, as the reader
    // draws it, then the paragraph carried on from the page before.
    const nextPage = '''
              <p style="color:brown;text-align:right;"> 152</p>
              <p class="noindentbodytext">ti vā … pe … abhinīharati.<span class="linebreak"></span><p>''';
    const before = ShownBlock(151,
        '<p class="bodytext">‘ taṃ jīvaṃ ’ ti vā ‘ aññaṃ sarīran ’<span class="linebreak"></span><p>');
    const after = ShownBlock(152, nextPage);

    test('is copied whole, without the page number', () {
      // As Flutter gives it: the number run into the text.
      const selected = '‘ taṃ jīvaṃ ’ ti vā ‘ aññaṃ sarīran ’\n 152ti vā … pe';
      expect(
          FormattedCopy.format(selected, [before, after], CopyFormat.plain)!
              .text,
          '‘ taṃ jīvaṃ ’ ti vā ‘ aññaṃ sarīran ’ ti vā … pe');
      expect(
          FormattedCopy.format(selected, [before, after], CopyFormat.markdown)!
              .text,
          '‘ taṃ jīvaṃ ’ ti vā ‘ aññaṃ sarīran ’ ti vā … pe');
    });

    test('with a translation between, carries on a line down', () {
      final bilingual = ShownBlock(
          151,
          _drawn(
              '<p class="bodytext"><span class="palitext">‘ aññaṃ sarīran ’</span>'
              '<br><span class="translation_text" lang="en">‘Is the soul …?’</span></p>'));
      const selected = '‘ aññaṃ sarīran ’\n‘Is the soul …?’152ti vā';
      expect(
          FormattedCopy.format(selected, [bilingual, after], CopyFormat.plain)!
              .text,
          '‘ aññaṃ sarīran ’\n‘Is the soul …?’\nti vā');
    });

    test('a page that starts a paragraph of its own is not joined', () {
      const fresh = ShownBlock(152,
          '<p style="color:brown;text-align:right;"> 152</p><p class="bodytext">380. pe</p>');
      expect(
          FormattedCopy.format(
                  'sarīran ’ 152 380. pe', [before, fresh], CopyFormat.plain)!
              .text,
          'sarīran ’\n\n380. pe');
    });
  });

  test('plain text keeps lines and paragraphs and has no source', () {
    final out = FormattedCopy.format(
        'Ekaṃ samayaṃ bhagavā. At one time the Blessed One. Mūlapariyāya Tatra',
        blocks,
        CopyFormat.plain,
        source: 'DN',
        link: (p) => 'x')!;
    expect(
        out.text,
        'Ekaṃ samayaṃ bhagavā.\nAt one time the Blessed One.\n\n'
        'Mūlapariyāya\n\nTatra');
  });

  test('variant readings and edition pages are copied as they are drawn', () {
    // The reader puts these in only when they are turned on in settings.
    const shown = ShownBlock(
        1,
        '<p class="bodytext">evaṃ <span class="note">[evaṃ (syā.)]</span> me '
        '<span style="color:brown;">[P 1.1]</span> sutaṃ</p>');
    expect(
        FormattedCopy.format('evaṃ [evaṃ (syā.)] me [P 1.1] sutaṃ', [shown],
                CopyFormat.plain)!
            .text,
        'evaṃ [evaṃ (syā.)] me [P 1.1] sutaṃ');
    const hidden = ShownBlock(1, '<p class="bodytext">evaṃ me sutaṃ</p>');
    expect(
        FormattedCopy.format('evaṃ me sutaṃ', [hidden], CopyFormat.plain)!.text,
        'evaṃ me sutaṃ');
  });
}
