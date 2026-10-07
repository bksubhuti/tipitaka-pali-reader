import 'package:flutter_test/flutter_test.dart';
import 'package:tipitaka_pali/utils/page_composer.dart';
import 'package:tipitaka_pali/utils/side_by_side.dart';

void main() {
  final sentences = [
    const PageSentence(
        paraId: 1,
        lineId: 1,
        pali: 'Evaṃ me sutaṃ.',
        paraNum: '1',
        translations: ['Thus have I heard.', 'ຂ້າພະເຈົ້າໄດ້ຍິນມາ']),
    const PageSentence(
        paraId: 1,
        lineId: 2,
        pali: 'Ekaṃ samayaṃ bhagavā.',
        translations: ['At one time the Blessed One.', '']),
    const PageSentence(
        paraId: 1, lineId: 3, pali: 'Tatra kho.', translations: ['', 'ທີ່ນັ້ນ']),
  ];
  final html = PageComposer.compose(sentences, languages: ['en', 'lo']);

  test('keeps only the first language', () {
    final kept = SideBySide.keepOnly(html, 'en');
    expect(kept, contains('Thus have I heard.'));
    expect(kept, isNot(contains('ຂ້າພະເຈົ້າ')));
    expect(kept, isNot(contains('ທີ່ນັ້ນ')));
  });

  test('cuts into one row per sentence, Pali beside its translation', () {
    var block = SideBySide.mark(SideBySide.keepOnly(html, 'en'));
    // As the reader leaves it: markers gone, a closing line break.
    block = block
        .replaceAll(PageComposer.sentenceMarkers, '')
        .replaceAll('</p>', '<span class="linebreak"></span><p>');
    final rows = SideBySide.split(block)!;
    expect(rows.length, 3);
    expect(rows[0].$1, startsWith('<p class="bodytext">'));
    expect(rows[0].$1, contains('Evaṃ me sutaṃ.'));
    expect(rows[0].$2, contains('Thus have I heard.'));
    expect(rows[1].$1, contains('Ekaṃ samayaṃ'));
    expect(rows[1].$2, contains('At one time'));
    expect(rows[2].$1, contains('Tatra kho.'));
    expect(rows[2].$2, isEmpty);
    for (final (l, r) in rows) {
      expect(l, isNot(contains(SideBySide.columnBreak)));
      expect('$l$r', isNot(contains(SideBySide.rowBreak)));
      expect(l, isNot(contains('<br>')));
    }
  });

  test('a block with no translation is not cut', () {
    final pali = PageComposer.compose(
        [const PageSentence(paraId: 1, lineId: 1, pali: 'Evaṃ me sutaṃ.')]);
    expect(SideBySide.split(SideBySide.mark(pali)), isNull);
    expect(SideBySide.split(PageComposer.translationCredit), isNull);
  });
}
