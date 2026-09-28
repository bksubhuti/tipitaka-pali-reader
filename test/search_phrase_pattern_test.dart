import 'package:flutter_test/flutter_test.dart';
import 'package:tipitaka_pali/services/repositories/fts_repo.dart';

/// Regression tests for the phrase matching exact search does in Dart, after
/// the database has already found a row.
///
/// This step once discarded correct results and nothing noticed. The database
/// found the passage, the code then failed to re-match the phrase in the text
/// and dropped the row, and the screen said the phrase could not be found. It
/// took someone typing a real query to see it, which is the reason these tests
/// exist.
///
/// The cause: a reader types words separated by spaces, while the text has
/// punctuation between them. "vadeyya culasilam" never matches
/// "vadeyya. Culasilam" literally.
void main() {
  RegExp tolerant(String phrase) => RegExp(
      FtsDatabaseRepository.phrasePattern(phrase, tolerant: true),
      caseSensitive: false);

  group('phrase matching against real text', () {
    test('matches across a full stop and a capital', () {
      const text = 'atha kho vadeyya. Cūḷasīlaṃ niṭṭhitaṃ. Majjhimasīlaṃ 11.';
      expect(tolerant('vadeyya cūḷasīlaṃ niṭṭhitaṃ majjhimasīlaṃ').hasMatch(text),
          isTrue);
    });

    test('matches across a quotation mark', () {
      const text = 'bhikkhusaṅghañcā ’ ti. ayaṃ kho no';
      expect(tolerant('bhikkhusaṅghañcā ti').hasMatch(text), isTrue);
    });

    test('matches when the phrase runs over a paragraph number', () {
      const text = 'vaṇṇaṃ vadamāno vadeyya. 8.‘‘‘ Pāṇātipātaṃ pahāya';
      expect(tolerant('vadeyya 8 pāṇātipātaṃ pahāya').hasMatch(text), isTrue);
    });

    test('still requires the words in order', () {
      const text = 'cūḷasīlaṃ niṭṭhitaṃ. vadeyya majjhimasīlaṃ';
      expect(tolerant('vadeyya cūḷasīlaṃ niṭṭhitaṃ').hasMatch(text), isFalse);
    });

    test('does not match a different word', () {
      const text = 'vadeyya. Mahāsīlaṃ niṭṭhitaṃ.';
      expect(tolerant('vadeyya cūḷasīlaṃ niṭṭhitaṃ').hasMatch(text), isFalse);
    });

    test('does not join across a word boundary', () {
      // "vade" must not match inside "vadeyya"
      const text = 'vadeyya cūḷasīlaṃ';
      expect(tolerant('vade cūḷasīlaṃ').hasMatch(text), isFalse);
    });

    test('a single word is unaffected', () {
      expect(tolerant('nibbāna').hasMatch('pana nibbāna hoti'), isTrue);
      expect(tolerant('nibbāna').hasMatch('pana nibbuti hoti'), isFalse);
    });
  });

  group('the page index keeps its old behaviour', () {
    test('matching is literal, punctuation and all', () {
      final strict = RegExp(
          FtsDatabaseRepository.phrasePattern('vadeyya cūḷasīlaṃ',
              tolerant: false),
          caseSensitive: false);
      expect(strict.hasMatch('vadeyya cūḷasīlaṃ'), isTrue);
      expect(strict.hasMatch('vadeyya. Cūḷasīlaṃ'), isFalse);
    });

    test('regex characters in a phrase are escaped, not interpreted', () {
      final strict = RegExp(
          FtsDatabaseRepository.phrasePattern('a.b', tolerant: false));
      expect(strict.hasMatch('a.b'), isTrue);
      expect(strict.hasMatch('axb'), isFalse);
    });
  });
}
