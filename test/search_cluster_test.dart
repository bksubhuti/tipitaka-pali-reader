import 'package:flutter_test/flutter_test.dart';
import 'package:tipitaka_pali/utils/search_cluster.dart';

void main() {
  const words = ['kusalā', 'dhammā', 'pacchimānaṃ'];
  const h = '<span class="highlighted">';

  // The page from the report: stray "dhammā" before the real match.
  const page = '<p>kāyāyatanaṃ taṃsampayuttakānañca ${h}dhammā</span>naṃ '
      'nissayapaccayena paccayo. <span class="translation_text">Body sense '
      'base is related.</span> 9. upanissayapaccayoti – purimā purimā '
      '${h}kusalā</span> ${h}dhammā</span> ${h}pacchimānaṃ</span> '
      '${h}pacchimānaṃ</span> ${h}kusalā</span>naṃ</p>';

  group('the scroll target', () {
    test('is the start of the group, not a stray word before it', () {
      final out =
          SearchCluster.markStart(page, 'highlighted', words, 10, 'goto');
      expect(out, contains('purimā <span id="goto" class="highlighted">kusalā'));
      expect(out.indexOf('id="goto"'), greaterThan(out.indexOf('9. ')));
    });

    test('falls back to the first highlight without a group', () {
      const lone = '<p>a ${h}dhammā</span> b ${h}kusalā</span></p>';
      final out =
          SearchCluster.markStart(lone, 'highlighted', words, 10, 'goto');
      expect(out, contains('a <span id="goto" class="highlighted">dhammā'));
    });

    test('a group too spread out for the distance is not one', () {
      final spread = '<p>${h}kusalā</span> one two three '
          '${h}dhammā</span> ${h}pacchimānaṃ</span></p>';
      expect(
          SearchCluster.markStart(spread, 'highlighted', words, 1, 'goto'),
          contains('<span id="goto" class="highlighted">kusalā'));
      expect(SearchCluster.hasGroup(spread, words, 1), isFalse);
      expect(SearchCluster.hasGroup(spread, words, 3), isTrue);
    });
  });

  group('a block holds the group', () {
    test('when the words come together in its text', () {
      expect(
          SearchCluster.hasGroup(
              '<p>purimā purimā kusalā dhammā pacchimānaṃ pacchimānaṃ</p>',
              words,
              10),
          isTrue);
    });

    test('not when it only has some of them', () {
      expect(
          SearchCluster.hasGroup(
              '<p>taṃsampayuttakānañca dhammānaṃ nissayapaccayena</p>',
              words,
              10),
          isFalse);
    });

    test('as prefixes, after an opening quote', () {
      expect(
          SearchCluster.hasGroup(
              '<p>“kusalānaṃ dhammānaṃ pacchimānaṃ</p>', words, 0),
          isTrue);
    });
  });
}
