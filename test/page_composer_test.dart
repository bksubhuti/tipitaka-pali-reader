import 'package:flutter_test/flutter_test.dart';
import 'package:tipitaka_pali/utils/page_composer.dart';

/// Layout, read without the sentence markers, which have tests of their own
/// below and would otherwise appear in every expected string.
String _compose(
  List<PageSentence> sentences, {
  bool continuesFromPreviousPage = false,
  List<String> languages = const [],
}) =>
    PageComposer.compose(sentences,
            continuesFromPreviousPage: continuesFromPreviousPage,
            languages: languages)
        .replaceAll(PageComposer.sentenceMarkers, '');

void main() {
  group('sentence markers', () {
    test('every sentence is marked where it begins', () {
      final html = PageComposer.compose(const [
        PageSentence(paraId: 6, lineId: 1, pali: 'evaṃ me sutaṃ'),
        PageSentence(paraId: 6, lineId: 2, pali: 'ekaṃ samayaṃ'),
      ]);
      expect(
          html,
          '<p class="bodytext"><a name="s6_1"></a>evaṃ me sutaṃ '
          '<a name="s6_2"></a>ekaṃ samayaṃ</p>');
    });

    test('a translation carries its language', () {
      final html = PageComposer.compose(const [
        PageSentence(
            paraId: 6,
            lineId: 1,
            pali: 'evaṃ me sutaṃ',
            translations: ['Thus have I heard', '', 'Так я слышал']),
      ], languages: const ['en', 'my', 'ru']);
      expect(html, contains('<span class="translation_text" lang="en">'
          'Thus have I heard</span>'));
      expect(html, contains('<span class="translation_text" lang="ru">'));
      expect(html, isNot(contains('lang="my"')), reason: 'empty is skipped');
    });

    test('markers are removed whole by the pattern', () {
      final html = PageComposer.compose(const [
        PageSentence(paraId: 12, lineId: 30, pali: 'evaṃ me sutaṃ'),
      ]);
      expect(html.replaceAll(PageComposer.sentenceMarkers, ''),
          '<p class="bodytext">evaṃ me sutaṃ</p>');
    });
  });

  group('headings', () {
    test('a heading is written with its level, ordinary text is not', () {
      final html = _compose(const [
        PageSentence(
            paraId: 4, lineId: 1, pali: '1. Brahmajālasuttaṃ', headingLevel: 2),
        PageSentence(
            paraId: 5, lineId: 1, pali: 'Paribbājakakathā', headingLevel: 4),
        PageSentence(paraId: 6, lineId: 1, pali: 'evaṃ me sutaṃ'),
      ]);
      expect(
          html,
          '<p class="heading2">1. Brahmajālasuttaṃ</p>'
          '<p class="heading4">Paribbājakakathā</p>'
          '<p class="bodytext">evaṃ me sutaṃ</p>');
    });

    test('a title line, and levels beyond seven, stay in range', () {
      expect(PageComposer.headingClass(0), 'heading0');
      expect(PageComposer.headingClass(9), 'heading7');
    });
  });

  group('PageComposer', () {
    test('opens a paragraph and closes it', () {
      final html = _compose(const [
        PageSentence(paraId: 6, lineId: 1, pali: 'evaṃ me sutaṃ'),
      ]);
      expect(html, '<p class="bodytext">evaṃ me sutaṃ</p>');
    });

    test('joins sentences of one paragraph with a single space', () {
      final html = _compose(const [
        PageSentence(paraId: 6, lineId: 1, pali: 'evaṃ me sutaṃ'),
        PageSentence(paraId: 6, lineId: 2, pali: 'ekaṃ samayaṃ'),
      ]);
      expect(html, '<p class="bodytext">evaṃ me sutaṃ ekaṃ samayaṃ</p>');
    });

    test('starts a new paragraph when para_id changes', () {
      final html = _compose(const [
        PageSentence(paraId: 6, lineId: 1, pali: 'evaṃ me sutaṃ'),
        PageSentence(paraId: 7, lineId: 1, pali: 'tena samayena'),
      ]);
      expect(
        html,
        '<p class="bodytext">evaṃ me sutaṃ</p>'
        '<p class="bodytext">tena samayena</p>',
      );
    });

    test('a glued sentence continues rather than indenting', () {
      final html = _compose(const [
        PageSentence(paraId: 6, lineId: 1, pali: 'evaṃ me sutaṃ'),
        PageSentence(
            paraId: 7,
            lineId: 1,
            pali: 'tena samayena',
            glue: GlueState.continues),
      ]);
      expect(html.contains('<p class="noindentbodytext">tena samayena</p>'),
          isTrue);
    });

    test('verse gets its own class', () {
      final html = _compose(const [
        PageSentence(
            paraId: 9, lineId: 1, pali: 'sabbe saṅkhārā', glue: GlueState.verse),
      ]);
      expect(html, '<p class="gatha1">sabbe saṅkhārā</p>');
    });

    test('a page beginning mid-sentence does not indent', () {
      final html = _compose(
        const [PageSentence(paraId: 6, lineId: 4, pali: 'buddhassa avaṇṇaṃ')],
        continuesFromPreviousPage: true,
      );
      expect(html, '<p class="noindentbodytext">buddhassa avaṇṇaṃ</p>');
    });

    test('paragraph gets an anchor but the number is not written twice', () {
      // ePitaka's sentence already opens with "5.", so the composer must not
      // print the number again; it only marks the paragraph for navigation.
      final html = _compose(const [
        PageSentence(
            paraId: 6, lineId: 1, pali: '5. evaṃ me sutaṃ', paraNum: '5'),
      ]);
      expect(
        html,
        '<p class="bodytext"><a name="para5"></a>5. evaṃ me sutaṃ</p>',
      );
      expect(html.contains('paranum'), isFalse);
    });

    group('page anchors', () {
      test('sit at the word, exactly as the original pages write them', () {
        // The real case from the first Digha volume: Myanmar page 2 begins at
        // "avannam", the word after "buddhassa".
        final html = _compose(const [
          PageSentence(
            paraId: 7,
            lineId: 3,
            pali: 'anekapariyāyena buddhassa avaṇṇaṃ bhāsati',
            anchors: [
              PageAnchor(edition: 'M', volume: 1, page: 2, wordIndex: 2),
            ],
          ),
        ]);
        expect(
          html,
          '<p class="bodytext">anekapariyāyena buddhassa'
          '<a name="M1.0002"></a> avaṇṇaṃ bhāsati</p>',
        );
      });

      test('an anchor at word zero precedes the text', () {
        final html = _compose(const [
          PageSentence(
            paraId: 7,
            lineId: 1,
            pali: 'piṭṭhito anubandhā',
            anchors: [
              PageAnchor(edition: 'M', volume: 1, page: 3, wordIndex: 0),
            ],
          ),
        ]);
        expect(
          html,
          '<p class="bodytext"><a name="M1.0003"></a>piṭṭhito anubandhā</p>',
        );
      });

      test('several editions can fall in one sentence', () {
        final html = _compose(const [
          PageSentence(
            paraId: 7,
            lineId: 1,
            pali: 'one two three four',
            anchors: [
              PageAnchor(edition: 'V', volume: 1, page: 12, wordIndex: 1),
              PageAnchor(edition: 'P', volume: 2, page: 345, wordIndex: 3),
            ],
          ),
        ]);
        expect(html.contains('one<a name="V1.0012"></a> two'), isTrue);
        expect(html.contains('three<a name="P2.0345"></a> four'), isTrue);
      });

      test('an anchor past the last word does not lose text', () {
        final html = _compose(const [
          PageSentence(
            paraId: 7,
            lineId: 1,
            pali: 'one two',
            anchors: [
              PageAnchor(edition: 'M', volume: 1, page: 9, wordIndex: 99),
            ],
          ),
        ]);
        expect(html, '<p class="bodytext">one two<a name="M1.0009"></a></p>');
      });
    });

    group('variant readings', () {
      test('are wrapped so the reader can hide them', () {
        final html = _compose(const [
          PageSentence(
            paraId: 9,
            lineId: 1,
            pali: 'bhagavantaṃ piṭṭhito anubandhā '
                '[anubaddhā (ka. sī. pī.)] honti',
          ),
        ]);
        expect(
          html,
          '<p class="bodytext">bhagavantaṃ piṭṭhito anubandhā '
          '<span class="note">[anubaddhā (ka. sī. pī.)]</span> honti</p>',
        );
      });

      test('a cross-reference is left alone', () {
        // Not a variant: no parenthesised source, so hiding it would take
        // away content rather than an alternative spelling.
        final html = _compose(const [
          PageSentence(paraId: 9, lineId: 1, pali: 'vuttaṃ [pāci.70] hoti'),
        ]);
        expect(html.contains('note'), isFalse);
        expect(html.contains('[pāci.70]'), isTrue);
      });

      test('several variants in one sentence are each wrapped', () {
        final html = _compose(const [
          PageSentence(
            paraId: 9,
            lineId: 1,
            pali: 'a [b (sī.)] c [d (syā.)] e',
          ),
        ]);
        expect(
          html,
          '<p class="bodytext">a <span class="note">[b (sī.)]</span> c '
          '<span class="note">[d (syā.)]</span> e</p>',
        );
      });
    });

    group('translations', () {
      test('a page with no translation is written exactly as before', () {
        // No palitext wrapper, because that wrapper is what tells the reader
        // the page is bilingual. A Pali-only page must look untouched.
        final html = _compose(const [
          PageSentence(paraId: 6, lineId: 1, pali: 'evaṃ me sutaṃ'),
        ]);
        expect(html.contains('palitext'), isFalse);
        expect(html, '<p class="bodytext">evaṃ me sutaṃ</p>');
      });

      test('Pali comes first, then each language in order', () {
        final html = _compose(const [
          PageSentence(
            paraId: 6,
            lineId: 1,
            pali: 'evaṃ me sutaṃ',
            translations: ['thus have I heard', 'ainsi ai-je entendu'],
          ),
        ]);
        expect(
          html,
          '<p class="bodytext">'
          '<span class="palitext">evaṃ me sutaṃ</span>'
          '<br><span class="translation_text">thus have I heard</span>'
          '<br><span class="translation_text">ainsi ai-je entendu</span>'
          '</p>',
        );
      });

      test('the next sentence starts a new line after a translation', () {
        // Without this the Pali of the next sentence runs on from the English
        // of the last one, and the two languages read as one paragraph.
        final html = _compose(const [
          PageSentence(
              paraId: 6,
              lineId: 1,
              pali: 'evaṃ me sutaṃ',
              translations: ['thus have I heard']),
          PageSentence(
              paraId: 6,
              lineId: 2,
              pali: 'ekaṃ samayaṃ',
              translations: ['on one occasion']),
        ]);
        expect(
          html,
          '<p class="bodytext">'
          '<span class="palitext">evaṃ me sutaṃ</span>'
          '<br><span class="translation_text">thus have I heard</span>'
          '<br>'
          '<span class="palitext">ekaṃ samayaṃ</span>'
          '<br><span class="translation_text">on one occasion</span>'
          '</p>',
        );
      });

      test('sentences without translations still join with a space', () {
        final html = _compose(const [
          PageSentence(paraId: 6, lineId: 1, pali: 'evaṃ me sutaṃ'),
          PageSentence(paraId: 6, lineId: 2, pali: 'ekaṃ samayaṃ'),
        ]);
        expect(html, '<p class="bodytext">evaṃ me sutaṃ ekaṃ samayaṃ</p>');
      });

      test('a missing translation for one sentence is skipped', () {
        final html = _compose(const [
          PageSentence(
            paraId: 6,
            lineId: 1,
            pali: 'evaṃ me sutaṃ',
            translations: ['', 'ainsi ai-je entendu'],
          ),
        ]);
        expect('translation_text'.allMatches(html).length, 1);
        expect(html.contains('ainsi ai-je entendu'), isTrue);
      });

      test('page anchors still sit at the right word when bilingual', () {
        final html = _compose(const [
          PageSentence(
            paraId: 7,
            lineId: 3,
            pali: 'anekapariyāyena buddhassa avaṇṇaṃ',
            anchors: [
              PageAnchor(edition: 'M', volume: 1, page: 2, wordIndex: 2),
            ],
            translations: ['in many ways'],
          ),
        ]);
        expect(
            html.contains(
                '<span class="palitext">anekapariyāyena buddhassa'
                '<a name="M1.0002"></a> avaṇṇaṃ</span>'),
            isTrue);
      });
    });

    test('a translation inherits the paragraphing and orphan control', () {
      // The paragraph structure and the keep-with-next flag were worked out
      // against the Pali. A translation is written inside the same paragraph
      // as the sentence it translates, rather than in a parallel structure,
      // so reading in one language alone keeps all of it.
      final html = _compose(const [
        PageSentence(
            paraId: 6,
            lineId: 1,
            pali: 'evaṃ me sutaṃ',
            translations: ['Thus have I heard.']),
        PageSentence(
            paraId: 7,
            lineId: 1,
            pali: 'atha kho',
            glue: GlueState.continues,
            translations: ['Then indeed.']),
        PageSentence(
            paraId: 8,
            lineId: 1,
            pali: 'sabbe saṅkhārā',
            glue: GlueState.verse,
            translations: ['All formations.']),
      ]);

      // Each translation sits inside the paragraph its Pali opened.
      final classes = RegExp(r'<p class="([^"]+)"')
          .allMatches(html)
          .map((m) => m.group(1))
          .toList();
      expect(classes, ['bodytext', 'noindentbodytext', 'gatha1']);

      for (final className in classes) {
        final block = RegExp('<p class="$className">(.*?)</p>', dotAll: true)
            .firstMatch(html)!
            .group(1)!;
        expect(block, contains('translation_text'),
            reason: '$className paragraph lost its translation');
      }
    });

    test('an empty page composes to nothing', () {
      expect(_compose(const []), '');
    });
  });
}
