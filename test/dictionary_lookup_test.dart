import 'package:flutter_test/flutter_test.dart';
import 'package:tipitaka_pali/ui/screens/dictionary/controller/dictionary_controller.dart';

/// A word tapped twice is looked up twice. The dictionary is told through a
/// value notifier, which says nothing when given the value it already has,
/// so a second tap on a word whose first lookup was missed did nothing.
void main() {
  test('the same word asked for twice is heard twice', () {
    final heard = <String>[];
    void listener() {
      final word = globalLookupWord.value;
      if (word != null) heard.add(word);
    }

    globalLookupWord.addListener(listener);
    addTearDown(() => globalLookupWord.removeListener(listener));

    lookUpWord('gahapatānīti');
    lookUpWord('gahapatānīti');
    expect(heard, ['gahapatānīti', 'gahapatānīti']);
    expect(globalLookupWord.value, 'gahapatānīti');
  });
}
