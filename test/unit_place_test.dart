import 'package:flutter_test/flutter_test.dart';

import 'package:tipitaka_pali/services/database/unit_text.dart';

/// Consecutive search units share a paragraph, so a hit in it came back
/// from both and was listed twice. A hit is placed by paragraph and offset
/// in it, which is the same from either unit.
void main() {
  // Paragraphs 1–2 and 2–3: paragraph 2 is in both.
  const shared = 'tādisan ti tumhādisaṃ';
  const a = UnitWithParagraphs('aaa bbb $shared', [0, 8], [1, 2]);
  const b = UnitWithParagraphs('$shared ccc', [0, 22], [2, 3]);

  test('the same hit is the same place from either unit', () {
    final inA = a.placeOf(a.text.indexOf('tumhādisaṃ'));
    final inB = b.placeOf(b.text.indexOf('tumhādisaṃ'));
    expect(inA, isNotNull);
    expect(inA, inB);
  });

  test('a different hit is a different place', () {
    expect(a.placeOf(0), (paragraph: 1, offset: 0));
    expect(b.placeOf(b.text.indexOf('ccc')), (paragraph: 3, offset: 0));
    expect(a.placeOf(0), isNot(b.placeOf(0)));
  });
}
