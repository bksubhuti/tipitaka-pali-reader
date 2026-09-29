import 'package:flutter_test/flutter_test.dart';
import 'package:tipitaka_pali/services/repositories/fts_repo.dart';

/// Where a search result opens the reader.
///
/// A passage is about a page long, so the difference between landing on the
/// match and landing at the top of the passage is the difference between
/// seeing the words and hunting for them. A distance search is the hard case:
/// its words are spread out, and the first stray occurrence of one of them is
/// not the answer.
void main() {
  group('locating the hit in a passage', () {
    test('a distance search lands where the words come together', () {
      // "dog" appears early on its own; the two words only meet much later.
      final text = 'the dog barked ${'filler ' * 60}'
          'seeing the ascetic he called his dogs to him';
      final at = FtsDatabaseRepository.locateHit(text, ['dog', 'ascetic'], 20);

      expect(at, greaterThan(text.indexOf('filler')),
          reason: 'landing on the lone early "dog" is the bug: the reader '
              'opens the page and the phrase is nowhere near');
      expect(text.substring(at), startsWith('ascetic'));
    });

    test('words that never come together still beat the top', () {
      final text = 'alpha ${'filler ' * 80}omega';
      final at = FtsDatabaseRepository.locateHit(text, ['omega', 'zeta'], 10);
      expect(at, text.indexOf('omega'),
          reason: 'one word found is better than the start of the passage');
    });

    test('a word absent from the passage does not land at nothing', () {
      final text = 'nothing here matches';
      expect(FtsDatabaseRepository.locateHit(text, ['absent'], 10), -1);
    });

    test('a needle matches the start of a word, not its middle', () {
      final text = 'anuruddha sudhamma kamma kammassa';
      final at = FtsDatabaseRepository.locateHit(text, ['kamma'], 10);
      expect(at, text.indexOf('kamma '),
          reason: '"kamma" should not match inside "sudhamma"');
    });

    test('Pali diacritics are part of a word', () {
      final text = 'suppiyopi kho paribbājako antarā ca';
      final at = FtsDatabaseRepository.locateHit(text, ['paribbājako'], 5);
      expect(at, text.indexOf('paribbājako'));
    });

    test('the first of several clusters wins', () {
      final text = 'dog ascetic ${'filler ' * 40}dog ascetic';
      final at = FtsDatabaseRepository.locateHit(text, ['dog', 'ascetic'], 20);
      expect(at, 0);
    });
  });
}
