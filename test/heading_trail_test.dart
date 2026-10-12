import 'package:flutter_test/flutter_test.dart';
import 'package:tipitaka_pali/services/repositories/heading_trail_repo.dart';

Map<String, Object?> _h(int level, String title, [String? sc]) =>
    {'level': level, 'title': title, 'sc_id': sc};

void main() {
  test('the nearest heading at each level, the book first', () {
    // epi.headings before D-i 695, the nearest first.
    final trail = HeadingTrail.fromRows([
      _h(4, 'Dvepabbajitavatthu', 'dn7'),
      _h(2, '7. Jāliyasuttaṃ', 'dn7'),
      _h(4, 'Dvepabbajitavatthu', 'dn6'),
      _h(2, '6. Mahālisuttaṃ', 'dn6'),
      _h(1, '(DN) Sīlakkhandhavaggapāḷi'),
    ])!;
    expect(trail.titles, [
      '(DN) Sīlakkhandhavaggapāḷi',
      '7. Jāliyasuttaṃ',
      'Dvepabbajitavatthu',
    ]);
    expect(trail.citation, 'DN 7');
  });

  test('every level there is, and the space after the nikaya', () {
    final trail = HeadingTrail.fromRows([
      _h(4, '4. Aruṇavatīsuttaṃ', 'sn6.14'),
      _h(4, '3. Brahmadevasuttaṃ', 'sn6.13'),
      _h(3, '2. Dutiyavaggo'),
      _h(2, '6. Brahmasaṃyuttaṃ'),
      _h(1, '(SN)Sagāthāvaggo'),
    ])!;
    expect(trail.titles, [
      '(SN) Sagāthāvaggo',
      '6. Brahmasaṃyuttaṃ',
      '2. Dutiyavaggo',
      '4. Aruṇavatīsuttaṃ',
    ]);
    expect(trail.citation, 'SN 6.14');
  });

  test('references cited the usual way only', () {
    expect(const HeadingTrail([], 'mn63').citation, 'MN 63');
    expect(const HeadingTrail([], 'dhp1-20').citation, 'Dhp 1-20');
    expect(const HeadingTrail([], 'pli-tv-bu-vb-pj3').citation, isNull);
    expect(const HeadingTrail([], null).citation, isNull);
    expect(HeadingTrail.fromRows([]), isNull);
  });
}
