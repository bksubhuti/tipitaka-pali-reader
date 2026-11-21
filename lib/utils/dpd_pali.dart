import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/business_logic/models/dictionary_book.dart';
import 'package:tipitaka_pali/services/provider/script_language_provider.dart';
import 'package:tipitaka_pali/utils/pali_script.dart';
import 'package:tipitaka_pali/utils/pali_script_converter.dart';

/// Pāḷi in the DPD Extras (inflections, families, frequency) in the script
/// of the dictionary they were opened from: a translation's own script
/// (Sinhala DPD, Sinhala letters), else the reader's script. The data is
/// Roman.
class DpdPali {
  DpdPali(BuildContext context, int book)
      : script = DictionaryBook.dpdScript(book) ??
            context.read<ScriptLanguageProvider>().currentScript;

  final Script script;

  static final _number = RegExp(r'^(.*?)(\s+[\d.]+)$');

  /// A word or headword; a homonym number ("dhamma 1.01") stays as it is.
  String call(String roman) {
    if (script == Script.roman || roman.isEmpty) return roman;
    final m = _number.firstMatch(roman);
    final word = m?.group(1) ?? roman;
    final rest = m?.group(2) ?? '';
    return PaliScript.getScriptOf(script: script, romanText: word) + rest;
  }
}
