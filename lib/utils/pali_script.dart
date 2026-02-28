import 'package:tipitaka_pali/utils/roman_to_sinhala.dart';

import './mm_pali.dart';
import './pali_script_converter.dart';

class PaliScript {
  // pali word not inside html tag
  static final _regexPaliWord =
      RegExp(r'[0-9a-zA-ZāīūṅñṭḍṇḷṃĀĪŪṄÑṬḌHṆḶṂ\.]+(?![^<>]*>)');
  PaliScript._();

  static Map<String, String> cache = {};

  static String getCachedScriptOf({
    required Script script,
    required String romanText,
    required String cacheId,
    bool isHtmlText = false,
  }) {
    if (cache[cacheId] == null || cache[cacheId]?.isEmpty == true) {
      cache[cacheId] = getScriptOf(
          script: script, romanText: romanText, isHtmlText: isHtmlText);
    }

    return cache[cacheId] ?? '';
  }

  // Regex to match translation block.
  // It matches the opening tag (e.g. <span class="translation_text...>) and
  // skips content until the closing tag, allowing for one level of nested tags of the same type.
  static final _regexTranslationBlock = RegExp(
      r'<([a-zA-Z0-9]+)[^>]*class="[^"]*\b(translation_text|english_text|vietnamese_text)\b[^"]*"[^>]*>(?:(?:(?!<\1|<\/\1>).)*|<\1[^>]*>(?:(?!<\1|<\/\1>).)*<\/\1>)*<\/\1>',
      caseSensitive: false);

  static String getScriptOf({
    required Script script,
    required String romanText,
    bool isHtmlText = false,
  }) {
    if (romanText.isEmpty) return romanText;

    if (!isHtmlText) {
      if (script == Script.myanmar) {
        return MmPali.fromRoman(romanText);
      } else if (script == Script.devanagari) {
        return toDeva(romanText);
      } else if (script == Script.sinhala) {
        return TextProcessor.convertFrom(romanText, Script.roman);
      } else {
        // janaka's converter is based on sinhala
        // cannot convert from roman to other lanuguage directly
        // so convert to sinhal fist and then convert to other
        final sinhala = TextProcessor.convertFrom(romanText, Script.roman);
        return TextProcessor.convert(sinhala, script);
      }
    } else {
      return romanText.splitMapJoin(
        _regexTranslationBlock,
        onMatch: (Match match) => match.group(0)!, // keep unchanged
        onNonMatch: (String nonMatch) {
          return nonMatch.replaceAllMapped(_regexPaliWord, (match) {
            final word = match.group(0)!;
            if (script == Script.myanmar) {
              return MmPali.fromRoman(word);
            } else if (script == Script.devanagari) {
              return toDeva(word);
            } else if (script == Script.sinhala) {
              return TextProcessor.convertFrom(word, Script.roman);
            } else {
              final sinhala = TextProcessor.convertFrom(word, Script.roman);
              return TextProcessor.convert(sinhala, script);
            }
          });
        },
      );
    }
  }

  static String getRomanScriptFrom(
      {required Script script, required String text}) {
    if (script == Script.myanmar) {
      return MmPali.toRoman(text);
    } else if (script == Script.sinhala) {
      return TextProcessor.convert(text, Script.roman);
    } else {
      // janaka's converter is based on sinhala
      // cannot convert from other lanuguage to roman directly
      // so convert to sinhal fist and then convert to roman
      final sinhala = TextProcessor.convertFrom(text, script);
      return TextProcessor.convert(sinhala, Script.roman);
    }
  }
}
