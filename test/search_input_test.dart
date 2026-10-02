import 'package:flutter_test/flutter_test.dart';

import 'package:tipitaka_pali/utils/pali_script_converter.dart';
import 'package:tipitaka_pali/utils/search_input.dart';

/// Which side a search goes to depends on the script the reader reads the
/// Pali in: the same Myanmar letters are Pali to one reader and Burmese to
/// another.
void main() {
  test('Roman letters search the Pali and the translations', () {
    final input = SearchInput.of('evaṃ me', readingScript: Script.roman);
    expect(input.isTranslationOnly, isFalse);
    expect(input.pali, 'evaṃ me');
    expect(input.wasConverted, isFalse);

    final english = SearchInput.of('form is not self',
        readingScript: Script.myanmar);
    expect(english.pali, 'form is not self');
  });

  test('the script the Pali is read in is Pali', () {
    final input = SearchInput.of('ဧဝံ', readingScript: Script.myanmar);
    expect(input.isTranslationOnly, isFalse);
    expect(input.pali, 'evaṃ');
    expect(input.asTyped, 'ဧဝံ');
    expect(input.wasConverted, isTrue);
  });

  test('another script is a translation, searched as typed', () {
    final input = SearchInput.of('စကားစမြည်', readingScript: Script.roman);
    expect(input.isTranslationOnly, isTrue);
    expect(input.pali, isEmpty);
    expect(input.asTyped, 'စကားစမြည်');

    final thai = SearchInput.of('ภิกษุ', readingScript: Script.myanmar);
    expect(thai.isTranslationOnly, isTrue);
  });

  test('a script no Pali is shown in is a translation', () {
    expect(SearchInput.of('世尊', readingScript: Script.roman).isTranslationOnly,
        isTrue);
    expect(
        SearchInput.of('ஆனந்த', readingScript: Script.roman).isTranslationOnly,
        isTrue);
  });

  test('digits alone are not taken for a translation', () {
    expect(SearchInput.of('22', readingScript: Script.roman).isTranslationOnly,
        isFalse);
  });
}
