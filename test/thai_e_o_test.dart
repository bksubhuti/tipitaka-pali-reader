import 'package:flutter_test/flutter_test.dart';
import 'package:tipitaka_pali/utils/pali_script.dart';
import 'package:tipitaka_pali/utils/pali_script_converter.dart';

// Thai writes e and o before the consonant (#334).
void main() {
  String toRoman(String thai) =>
      PaliScript.getRomanScriptFrom(script: Script.thai, text: thai);
  String toThai(String roman) =>
      PaliScript.getScriptOf(script: Script.thai, romanText: roman);

  test('a leading vowel is read after its consonant', () {
    expect(toRoman('เตน'), 'tena');
    expect(toRoman('โส'), 'so');
  });

  test('and after the whole of a phinthu cluster', () {
    expect(toThai('sve'), 'เสฺว');
    expect(toRoman('เสฺว'), 'sve');
  });

  test('Roman to Thai and back is unchanged', () {
    for (final word in ['tena', 'bhikkhave', 'sotāpanno', 'svākkhāto',
        'evaṃ', 'dvemā', 'tvevā']) {
      expect(toRoman(toThai(word)), word, reason: toThai(word));
    }
  });
}
