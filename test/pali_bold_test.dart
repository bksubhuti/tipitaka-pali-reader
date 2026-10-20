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

    test('a term only in quotes is made bold', () {
      expect(
          compose('Tattha <b>sabbadhammamūlapariyāyan</b>ti sabbesaṃ.',
              'In this context, ‘the root of all phenomena’ means the root-cause.'),
          contains('<b>‘the root of all phenomena’</b> means'));
    });

    test('only as many quotes as the Pali bolds', () {
      expect(
          compose('<b>sabba</b> -saddo.',
              'this word ‘all’, as in ‘all form is impermanent’.'),
          allOf(contains('<b>‘all’</b>'),
              contains(' ‘all form is impermanent’')));
    });

    test('an apostrophe inside a word does not end the quote', () {
      expect(
          compose('<b>Hatthipadan</b>ti.', '‘The Elephant’s Footprint’ is …'),
          contains('<b>‘The Elephant’s Footprint’</b>'));
    });

    test('a translation already bold is left alone', () {
      expect(
          compose(
              '<b>Evaṃ me sutan</b>ti.', '<b>‘Thus have I heard’</b> refers'),
          contains('<b>‘Thus have I heard’</b> refers'));
    });

    test('a quote is bolded where the Pali has its bold, not first', () {
      final html = compose(
          'ñatvā ‘‘ abhabbā ime ’’ ti … <b>sabbadhammamūlapariyāyan</b>ti '
              'desanaṃ ārabhi.',
          'thought: “They are incapable.” … began the discourse called '
              '‘The Root of All Phenomena’ in order to');
      expect(html, contains('<b>‘The Root of All Phenomena’</b>'));
      expect(html, contains('thought: “They are incapable.”'));
    });

    test('quotes that do not line up are left alone', () {
      final html = compose(
          '‘‘ abhabbā ’’ ti <b>Mūlan</b>ti.', '‘one’ and ‘two’ and ‘three’');
      expect(html, isNot(contains('<b>')));
    });
  });
}
