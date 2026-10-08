import 'package:tipitaka_pali/utils/page_composer.dart';
import 'package:tipitaka_pali/utils/pali_script.dart';
import 'package:tipitaka_pali/utils/pali_script_converter.dart';

/// One thing to say: a sentence, in one language.
class TtsUtterance {
  final int page;

  /// The sentence's marker name, `s12_3`, which is how the reader finds it on
  /// the page to highlight it.
  final String sentence;

  /// [TtsPlan.pali] or a translation's language code.
  final String language;

  /// What the engine is given: Pali already in the script of its voice.
  final String text;

  const TtsUtterance({
    required this.page,
    required this.sentence,
    required this.language,
    required this.text,
  });
}

/// What to read aloud from a page, and in which voice.
///
/// Sentence by sentence, each in every chosen language before moving on:
/// the Pali, then its translations in the order the reader shows them. So a
/// listener hears a sentence and then what it means, the way the page reads.
///
/// Pali goes to the engine in Kannada script, to be read by a Kannada voice.
/// No engine has a Pali voice; Kannada spells Pali sounds one for one and
/// its voices read the result well. Devanagari with a Hindi voice was tried
/// and drops the final short a, which Pali cannot lose.
///
/// Where the device has a Sinhala voice, as Android usually does, the Pali
/// can be read in Sinhala instead: Sinhala script, Sinhala voice. That is
/// how a Sri Lankan listener is used to hearing it.
///
/// Windows has neither a Kannada nor a Sinhala voice, but can have a Hindi
/// one. There the Pali goes to it in Devanagari, final short a and all,
/// since some Pali is better than none.
class TtsPlan {
  TtsPlan._();

  /// The language code used for the Pali itself.
  static const pali = 'pali';

  /// The voices the Pali can be read with, by key: the engine language and
  /// the script the Pali is turned into for it.
  static const paliVoices = {
    'kn': PaliVoice('kn-IN', Script.kannada, 'Kannada'),
    'si': PaliVoice('si-LK', Script.sinhala, 'Sinhala'),
    'hi': PaliVoice('hi-IN', Script.devanagari, 'Hindi'),
  };

  /// Which of [paliVoices] reads the Pali. Set from the reader's choice
  /// before reading starts; Kannada unless they chose otherwise.
  static String paliVoiceKey = 'kn';

  static PaliVoice get paliVoice =>
      paliVoices[paliVoiceKey] ?? paliVoices['kn']!;

  /// The engine language for each translation's code.
  static const voiceLanguage = {
    'en': 'en-US',
    'my': 'my-MM',
    'si': 'si-LK',
    'th': 'th-TH',
    'vi': 'vi-VN',
    'zh': 'zh-CN',
    'km': 'km-KH',
    'lo': 'lo-LA',
    'hi': 'hi-IN',
    'ru': 'ru-RU',
    'pt': 'pt-BR',
    'de': 'de-DE',
    'ja': 'ja-JP',
    'ta': 'ta-IN',
  };

  static String voiceFor(String language) => language == pali
      ? paliVoice.engineLanguage
      : voiceLanguage[language] ?? language;

  /// The utterances for one page.
  ///
  /// [pageLanguages] is the language of each translation the page's
  /// sentences carry, in order; [chosen] is what the listener asked to hear.
  /// [from] starts part way down the page, at that sentence.
  static List<TtsUtterance> forPage(
    int page,
    List<PageSentence> sentences,
    List<String> pageLanguages,
    Set<String> chosen, {
    String? from,
  }) {
    final out = <TtsUtterance>[];
    var started = from == null;
    for (final sentence in sentences) {
      final key = PageComposer.sentenceMarker(sentence.paraId, sentence.lineId);
      if (!started) {
        if (key != from) continue;
        started = true;
      }
      if (chosen.contains(pali)) {
        final text = speakablePali(sentence.pali);
        if (text.isNotEmpty) {
          out.add(TtsUtterance(
              page: page, sentence: key, language: pali, text: text));
        }
      }
      for (var i = 0;
          i < pageLanguages.length && i < sentence.translations.length;
          i++) {
        final code = pageLanguages[i];
        if (!chosen.contains(code)) continue;
        final text = _clean(sentence.translations[i]);
        if (text.isEmpty) continue;
        out.add(TtsUtterance(
            page: page, sentence: key, language: code, text: text));
      }
    }
    // A start that is not on this page reads the page from the top rather
    // than reading nothing.
    if (!started) {
      return forPage(page, sentences, pageLanguages, chosen);
    }
    return out;
  }

  static final _tag = RegExp(r'<[^>]*>');
  static final _space = RegExp(r'\s+');

  /// A variant reading, `[anubaddhā (ka. sī. pī.)]`: an alternative and the
  /// editions it comes from. Read aloud, it interrupts the sentence with a
  /// list of abbreviations.
  static final _variant = RegExp(r'\[[^\[\]]*\([^()]*\)\s*\]');

  /// The paragraph number ePitaka opens a paragraph with, `59.`.
  static final _paragraphNumber = RegExp(r'^\s*[\d\-–]+\.\s*');

  static String _clean(String text) =>
      text.replaceAll(_tag, ' ').replaceAll(_space, ' ').trim();

  /// The Pali as it should be spoken, in the script of its voice.
  static String speakablePali(String pali) {
    final roman = _clean(pali)
        .replaceAll(_variant, ' ')
        .replaceFirst(_paragraphNumber, '')
        .replaceAll(_space, ' ')
        .trim();
    if (roman.isEmpty) return '';
    return PaliScript.getScriptOf(script: paliVoice.script, romanText: roman);
  }
}

/// A voice the Pali can be read with.
class PaliVoice {
  /// What the speech engine calls it, e.g. 'si-LK'.
  final String engineLanguage;

  /// The script the Pali is written in for it.
  final Script script;

  /// What to call it in the interface.
  final String name;

  const PaliVoice(this.engineLanguage, this.script, this.name);
}
