import 'package:flutter_test/flutter_test.dart';
import 'package:tipitaka_pali/services/repositories/sentence_page_content_repo.dart';
import 'package:tipitaka_pali/utils/page_composer.dart';

/// A commentary bolds the word it explains: `<b>Gahapatānī</b>ti`. Every tag
/// was once dropped from the reader's text to keep word offsets simple, and
/// the bold went with them, from 3.0.0 on, until a reader's teacher asked
/// where it had gone.
void main() {
  group('bold left open by a sentence or a page break is closed', () {
    String balance(String s) => SentencePageContentRepository.balanceBold(s);

    test('a whole bold is left alone', () {
      expect(balance('<b>Gahapatānī</b>ti gharasāminī.'),
          '<b>Gahapatānī</b>ti gharasāminī.');
    });

    test('one opened and not closed is closed at the end', () {
      expect(balance('<b>evaṃ abhiññābalaṃ patvā'),
          '<b>evaṃ abhiññābalaṃ patvā</b>');
    });

    test('one closed and never opened is opened at the start', () {
      expect(
          balance('loke udapādī</b>ti ettha'), '<b>loke udapādī</b>ti ettha');
    });

    test('plain text is unchanged', () {
      expect(balance('evaṃ me sutaṃ'), 'evaṃ me sutaṃ');
    });
  });

  group('the page draws it as the old pages did', () {
    test('as the bold class', () {
      final html = PageComposer.compose(const [
        PageSentence(
            paraId: 1866, lineId: 4, pali: '<b>Gahapatānī</b>ti gharasāminī.'),
      ]).replaceAll(PageComposer.sentenceMarkers, '');
      expect(
          html, contains('<span class="bld">Gahapatānī</span>ti gharasāminī.'));
    });

    test('with a page marker still at its word', () {
      final html = PageComposer.compose(const [
        PageSentence(
            paraId: 1,
            lineId: 1,
            pali: '<b>Tādisan</b>ti tumhādisaṃ.',
            anchors: [
              PageAnchor(edition: 'M', volume: 1, page: 42, wordIndex: 1)
            ]),
      ]).replaceAll(PageComposer.sentenceMarkers, '');
      expect(
          html,
          contains('<span class="bld">Tādisan</span>ti'
              '<a name="M1.0042"></a> tumhādisaṃ.'));
    });
  });

  group('the translation of a bolded word is bold too', () {
    String compose(String pali, String translation) => PageComposer.compose([
          PageSentence(
              paraId: 1866, lineId: 4, pali: pali, translations: [translation]),
        ], languages: const [
          'en'
        ]).replaceAll(PageComposer.sentenceMarkers, '');

    test('its italics become bold', () {
      expect(
          compose('<b>Gahapatānī</b>ti gharasāminī.',
              '<i>Gahapatānī</i> is a housewife.'),
          contains('<b>Gahapatānī</b> is a housewife.'));
    });

    test('italics stay italic where the Pali bolds nothing', () {
      expect(
          compose(
              'atha vā vedoti paññā vuccati', 'wisdom is called <i>veda</i>'),
          contains('wisdom is called <i>veda</i>'));
    });
  });
}
