import 'package:flutter_test/flutter_test.dart';
import 'package:tipitaka_pali/utils/fts_text_extractor.dart';

void main() {
  group('FtsTextExtractor', () {
    test(
        'extracts full Pali text with nested bld and paranum spans (page 304 case)',
        () {
      const html = '''
<p class="subhead"><span class="palitext">Tiracchānagatavatthukathā</span> 	<br/> 	<span class="translation_text english_text"><span class="centre">The Narrative of the Animal</span></span></p>
<p class="bodytext"> <span class="palitext"><span class="paranum">111</span>. <span class="bld">Nāgayoniyā</span>  <span class="bld">aṭṭīyatī</span>ti ettha kiñcāpi so pavattiyaṃ kusalavipākena devasampattisadisaṃ issariyasampattiṃ anubhoti, akusalavipākapaṭisandhikassa  pana tassa sajātiyā methunapaṭisevane ca vissaṭṭhaniddokkamane ca nāgasarīraṃ pātubhavati udakasañcārikaṃ maṇḍūkabhakkhaṃ, tasmā so tāya nāgayoniyā aṭṭīyati.</span> 	<br/> 	<span class="translation_text english_text">Here, in <span class="bld">"he is distressed by being a nāga"</span>, although he experiences sovereignty and prosperity.</span>
<br/>  <span class="palitext"><span class="bld">Harāyatī</span>ti lajjati.</span> 	<br/> 	<span class="translation_text english_text"><span class="bld">Harāyati</span> means he is ashamed.</span>
<br/>  <span class="palitext"><span class="bld">Jigucchatī</span>ti attabhāvaṃ jigucchati.</span> 	<br/> 	<span class="translation_text english_text"><span class="bld">Jigucchatī</span> means he is disgusted with his own existence.</span>
<br/>  <span class="palitext"><span class="bld">Tiracchānagato bhikkhave</span>ti ettha nāgo vā hotu supaṇṇamāṇavakādīnaṃ vā aññataro, antamaso sakkaṃ devarājānaṃ upādāya yo koci amanussajātiyo, sabbova imasmiṃ atthe tiracchānagatoti veditabbo.</span> 	<br/> 	<span class="translation_text english_text">Here, in <span class="bld">"bhikkhus, an animal"</span>, whether it be a nāga or any other, such as Supaṇṇamāṇavaka and the like, even Sakka, the king of devas, or any non-human being whatsoever, all are to be understood as "animals" in this context.</span>
<br/>  <span class="palitext">So neva upasampādetabbo, na pabbājetabbo, upasampannopi nāsetabboti.</span>
<p class="centre"><span class="palitext">Tiracchānagatavatthukathā niṭṭhitā.</span></p>
''';

      final paliText = FtsTextExtractor.extractPaliText(html);

      // Must contain supaṇṇamāṇavakādīnaṃ which was previously dropped by the non-greedy regex
      expect(paliText, contains('supaṇṇamāṇavakādīna'));
      expect(paliText, contains('supaṇṇamāṇavakādīnaṃ'));

      // Must contain text after nested paranum and bld spans
      expect(paliText, contains('Nāgayoniyā'));
      expect(paliText, contains('aṭṭīyatīti'));
      expect(paliText, contains('ti lajjati'));
      expect(paliText, contains('ti attabhāvaṃ jigucchati'));

      // Must NOT contain English translation text
      expect(paliText.contains('The Narrative of the Animal'), isFalse);
      expect(paliText.contains('king of devas'), isFalse);
    });

    test('extracts full translation text with nested spans', () {
      const html = '''
<p class="bodytext"> <span class="palitext"><span class="bld">Tiracchānagato bhikkhave</span>ti ettha nāgo vā hotu.</span>
<br/> <span class="translation_text english_text">Here, in <span class="bld">"bhikkhus, an animal"</span>, whether it be a nāga or any other, such as Supaṇṇamāṇavaka and the like, even Sakka, the king of devas.</span>
''';

      final transText = FtsTextExtractor.extractTranslationText(html);

      // Must preserve the full sentence after the inner <span class="bld"> tag
      expect(transText,
          contains('Here, in bhikkhus, an animal, whether it be a nāga'));
      expect(
          transText,
          contains(
              'Supaṇṇamāṇavaka and the like, even Sakka, the king of devas'));

      // Must NOT contain Pali text
      expect(transText.contains('Tiracchānagato'), isFalse);
    });

    test('handles unilingual Pali HTML without palitext spans', () {
      const html = '''
<p class="bodytext"><span class="paranum">1</span>. Evaṃ me sutaṃ—ekaṃ samayaṃ bhagavā sāvatthiyaṃ viharati jetavane anāthapiṇḍikassa ārāme.</p>
''';

      final paliText = FtsTextExtractor.extractPaliText(html);
      expect(paliText, contains('1. Evaṃ me sutaṃ'));
      expect(paliText, contains('anāthapiṇḍikassa ārāme.'));

      final transText = FtsTextExtractor.extractTranslationText(html);
      expect(transText, isEmpty);
    });

    test('handles deep nesting of spans', () {
      const html = '''
<p><span class="palitext">outer <span>middle <span>inner</span> still middle</span> still outer</span></p>
''';

      final paliText = FtsTextExtractor.extractPaliText(html);
      expect(paliText, equals('outer middle inner still middle still outer'));
    });
  });
}
