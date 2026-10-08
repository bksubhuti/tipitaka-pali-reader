import 'package:flutter_test/flutter_test.dart';

import 'package:tipitaka_pali/services/tts/tts_plan.dart';
import 'package:tipitaka_pali/utils/page_composer.dart';

/// What gets read aloud, in what order and in which voice.
void main() {
  const sentences = [
    PageSentence(
        paraId: 1,
        lineId: 1,
        pali: '1. Evaṃ me sutaṃ – ekaṃ samayaṃ bhagavā campāyaṃ viharati.',
        translations: ['Thus have I heard.', '']),
    PageSentence(
        paraId: 1,
        lineId: 2,
        pali: 'Atha kho pesso [peso (ka.)] ca hatthārohaputto.',
        translations: ['Then Pessa.', 'Тогда Песса.']),
  ];

  test('Pali can go to a Sinhala voice in Sinhala script instead', () {
    TtsPlan.paliVoiceKey = 'si';
    try {
      expect(TtsPlan.voiceFor(TtsPlan.pali), 'si-LK');
      expect(TtsPlan.speakablePali('evaṃ me sutaṃ'), 'එවං මෙ සුතං');
      // Translations keep their own voices.
      expect(TtsPlan.voiceFor('en'), 'en-US');
    } finally {
      TtsPlan.paliVoiceKey = 'kn';
    }
  });

  test('on Windows the Pali goes to a Hindi voice in Devanagari', () {
    TtsPlan.paliVoiceKey = 'hi';
    try {
      expect(TtsPlan.voiceFor(TtsPlan.pali), 'hi-IN');
      expect(TtsPlan.speakablePali('evaṃ me sutaṃ'), 'एवं मे सुतं');
    } finally {
      TtsPlan.paliVoiceKey = 'kn';
    }
  });

  test('Pali goes to the engine in Kannada script', () {
    // The listener's own sample, which reads well with a Kannada voice.
    expect(TtsPlan.speakablePali('Evaṃ me sutaṃ – ekaṃ samayaṃ bhagavā'),
        'ಏವಂ ಮೇ ಸುತಂ – ಏಕಂ ಸಮಯಂ ಭಗವಾ');
    expect(TtsPlan.voiceFor(TtsPlan.pali), 'kn-IN');
  });

  test('paragraph numbers and variant readings are not read out', () {
    final text = TtsPlan.speakablePali(sentences[1].pali);
    expect(text, isNot(contains('[')));
    expect(text, isNot(contains('ಕ.')), reason: 'the (ka.) source');
    expect(TtsPlan.speakablePali(sentences[0].pali), startsWith('ಏವಂ'));
  });

  test('each sentence in every chosen language before the next', () {
    final plan = TtsPlan.forPage(
        5, sentences, const ['en', 'ru'], {TtsPlan.pali, 'en', 'ru'});
    expect(plan.map((u) => '${u.sentence}:${u.language}').toList(), [
      's1_1:pali', 's1_1:en', // no Russian for the first sentence
      's1_2:pali', 's1_2:en', 's1_2:ru',
    ]);
    expect(plan.every((u) => u.page == 5), isTrue);
  });

  test('only what was chosen: English alone', () {
    final plan =
        TtsPlan.forPage(5, sentences, const ['en', 'ru'], {'en'});
    expect(plan.map((u) => u.text).toList(),
        ['Thus have I heard.', 'Then Pessa.']);
  });

  test('starts at the sentence asked for', () {
    final plan = TtsPlan.forPage(
        5, sentences, const ['en', 'ru'], {TtsPlan.pali},
        from: 's1_2');
    expect(plan.map((u) => u.sentence).toList(), ['s1_2']);
  });

  test('a start not on the page reads the page from the top', () {
    final plan = TtsPlan.forPage(
        5, sentences, const ['en', 'ru'], {TtsPlan.pali},
        from: 's99_1');
    expect(plan.length, 2);
  });
}
