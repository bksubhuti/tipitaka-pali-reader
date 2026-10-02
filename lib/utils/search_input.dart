import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/utils/pali_script.dart';
import 'package:tipitaka_pali/utils/pali_script_converter.dart';
import 'package:tipitaka_pali/utils/script_detector.dart';

/// What a search box holds: Pali, or words of a translation.
///
/// Nothing in the letters says which. Myanmar letters are Pali to a reader
/// who reads the Pali in Myanmar script, and Burmese to one reading it in
/// Roman. So the reader's own script decides:
///
///  * Roman letters are Pali or English, and both are searched, as always.
///  * The script the Pali is shown in is Pali. It is turned into Roman
///    letters for the Pali index, and the translations are searched with it
///    as typed as well.
///  * Any other script is a translation's language, searched as typed in the
///    translations alone. Turned into Roman Pali, as it used to be, it
///    matched nothing in either.
///
/// Pali typed in a script other than the one being read is therefore taken
/// for a translation. The reader switches script to search Pali in it.
class SearchInput {
  /// For the Pali index, in Roman letters. Empty for a translation's words.
  final String pali;

  /// For the translations, as typed.
  final String asTyped;

  const SearchInput._(this.pali, this.asTyped);

  bool get isTranslationOnly => pali.isEmpty;

  /// Whether the Pali side was given a converted form, so the two differ.
  bool get wasConverted => pali.isNotEmpty && pali != asTyped;

  static final _letter = RegExp(r'\p{L}', unicode: true);

  factory SearchInput.of(String text, {Script? readingScript}) {
    final reading = readingScript ?? _readingScript();
    final script = ScriptDetector.getLanguage(text);
    if (script == Script.roman) {
      // Roman, or a script the detector does not know, such as Chinese or
      // Tamil, which no Pali is shown in.
      final hasRoman = ScriptDetector.isRoman(text);
      if (!hasRoman && text.contains(_letter)) {
        return SearchInput._('', text);
      }
      return SearchInput._(text, text);
    }
    if (script == reading) {
      return SearchInput._(
          PaliScript.getRomanScriptFrom(script: script, text: text), text);
    }
    return SearchInput._('', text);
  }

  static Script _readingScript() {
    final code = Prefs.currentScriptLanguage;
    for (final info in listOfScripts) {
      if (info.localeCode == code) return info.script;
    }
    return Script.roman;
  }
}
