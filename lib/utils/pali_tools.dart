import 'package:tipitaka_pali/services/prefs.dart';

final variations = {
  'a': RegExp(r'ā'),
  'u': RegExp(r'ū'),
  't': RegExp(r'ṭ'),
  'n': RegExp(r'[ñṇṅ]'),
  'i': RegExp(r'ī'),
  'd': RegExp(r'ḍ'),
  'l': RegExp(r'ḷ'),
  'm': RegExp(r'[ṁṃ]')
};

class PaliTools {
  PaliTools._();
  static String velthuisToUni({required String velthiusInput}) {
    if (velthiusInput.isEmpty) return velthiusInput;
    if (Prefs.disableVelthuis) return velthiusInput;
    // Off by itself when the Pāḷi is shown in a script other than Roman:
    // those readers type in their own script, and aa, ii and the like
    // turning into ā and ī would get in their way.
    if (Prefs.currentScriptLanguage != defaultScriptLanguage) {
      return velthiusInput;
    }

    const nigahita = 'ṃ';
    const capitalNigahita = 'Ṃ';

    final uni = velthiusInput
        .replaceAll('aa', 'ā')
        .replaceAll('ii', 'ī')
        .replaceAll('uu', 'ū')
        .replaceAll('.t', 'ṭ')
        .replaceAll('.d', 'ḍ')
        .replaceAll('"n', 'ṅ') // double quote
        .replaceAll('\u201Dn', 'ṅ') // \u201D = Right Double Quotation Mark
        .replaceAll('“n', 'ṅ') // apple curly quote
        .replaceAll('”n', 'ṅ') // apple curlyquote
        .replaceAll(';n', 'ṅ') // my easier vel ṅ
        .replaceAll('~n', 'ñ')
        .replaceAll(';y', 'ñ') // my easier vel ñ
        .replaceAll('.n', 'ṇ')
        .replaceAll('.m', nigahita)
        .replaceAll('\u1E41', nigahita) // ṁ
        .replaceAll('.l', 'ḷ')
        .replaceAll('AA', 'Ā')
        .replaceAll('II', 'Ī')
        .replaceAll('UU', 'Ū')
        .replaceAll('.T', 'Ṭ')
        .replaceAll('.D', 'Ḍ')
        .replaceAll('"N', 'Ṅ')
        .replaceAll('\u201DN', 'Ṅ')
        .replaceAll('~N', 'Ñ')
        .replaceAll('.N', 'Ṇ')
        .replaceAll('.M', capitalNigahita)
        .replaceAll('\u1E40', capitalNigahita) // Ṁ
        .replaceAll('.L', 'Ḷ')
        .replaceAll('.ll', 'ḹ')
        .replaceAll('.r', 'ṛ')
        .replaceAll('.rr', 'ṝ')
        .replaceAll('.s', 'ṣ')
        .replaceAll('"s', 'ś')
        .replaceAll('\u201Ds', 'ś')
        .replaceAll('.h', 'ḥ');

    return uni;
  }

  static String toPlain(String word) {
    var plain = word.toLowerCase().trim();
    variations.forEach((key, value) {
      plain = plain.replaceAll(value, key);
    });
    return plain;
  }

}
