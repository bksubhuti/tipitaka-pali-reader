import 'package:flutter_test/flutter_test.dart';
import 'package:tipitaka_pali/services/repositories/xray_repo.dart';
import 'package:tipitaka_pali/utils/page_composer.dart';
import 'package:tipitaka_pali/utils/side_by_side.dart';

void main() {
  group('the term a commentary sentence takes up', () {
    test('is its opening bold, in lower case', () {
      expect(
          XrayRepository.termOf('<b>Nandivisālo nāmā</b>ti nandīti tassa '
              'balībaddassa nāmaṃ, <b>‘‘ nandivisālo ’’</b>ti vuccati.'),
          'nandivisālo nāmā');
    });

    test('puts back the ṃ written n before ti', () {
      expect(XrayRepository.termOf('<b>Evan</b>ti nipātapadaṃ.'), 'evaṃ');
    });

    test('loses quotes and punctuation at its edges', () {
      expect(XrayRepository.termOf('<b>‘‘Sutaṃ,’’</b>ti'), 'sutaṃ');
    });

    test('is empty when nothing is bold', () {
      expect(XrayRepository.termOf('plain text'), '');
    });
  });

  group('the X-ray tag', () {
    const pali = 'Atha kho nandivisālo balībaddo.';

    test('closes the Pali of a sentence with links', () {
      final html = PageComposer.compose(
          [const PageSentence(paraId: 38, lineId: 20, pali: pali, xrayId: 7)]);
      expect(html, contains('$pali<xray data-x="7"></xray>'));
      expect(html.replaceAll(PageComposer.xrayTags, ''),
          isNot(contains('xray')));
    });

    test('stays on the Pali side when drawn side by side', () {
      final html = PageComposer.compose([
        const PageSentence(
            paraId: 38,
            lineId: 20,
            pali: pali,
            xrayId: 7,
            translations: ['Then the ox.'])
      ], languages: [
        'en'
      ]);
      final rows = SideBySide.split(SideBySide.mark(html))!;
      expect(rows.single.$1, contains('<xray data-x="7"></xray>'));
      expect(rows.single.$2, isNot(contains('xray')));
    });

    test('is not written for a sentence without links', () {
      final html = PageComposer.compose(
          [const PageSentence(paraId: 1, lineId: 1, pali: pali)]);
      expect(html, isNot(contains('xray')));
    });
  });
}
