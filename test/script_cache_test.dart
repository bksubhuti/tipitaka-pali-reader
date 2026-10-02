import 'package:flutter_test/flutter_test.dart';

import 'package:tipitaka_pali/utils/pali_script.dart';
import 'package:tipitaka_pali/utils/pali_script_converter.dart';

/// The converted-text cache is keyed by place — book, chunk, script — and a
/// place's content changes when a translation is switched on. Keyed by place
/// alone, the old text came back for the rest of the session.
void main() {
  test('a chunk whose content changed is converted again', () {
    const id = 'book-mula_di_01-3-roman';
    final one = PaliScript.getCachedScriptOf(
        script: Script.roman,
        romanText: '<p>evaṃ me sutaṃ</p>',
        cacheId: id,
        isHtmlText: true);
    final two = PaliScript.getCachedScriptOf(
        script: Script.roman,
        romanText: '<p>evaṃ me sutaṃ<br><span class="translation_text">'
            'Thus have I heard</span></p>',
        cacheId: id,
        isHtmlText: true);
    expect(one, isNot(contains('Thus have I heard')));
    expect(two, contains('Thus have I heard'));
  });
}
