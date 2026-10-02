import 'package:tipitaka_pali/utils/pali_script_converter.dart';

class ScriptDetector {
  ScriptDetector._();
  static final _regexMM = RegExp('[\u1000-\u109F]');
  static final _regexRoman = RegExp(r'[a-zA-ZāīūṅñṭḍṇḷṃĀĪŪṄÑṬḌHṆḶṂ]');
  // static final _regexRoman = RegExp('[\u0000-\u017F\u1E00-\u1EFF]');
  static final _regexSinhala = RegExp('[\u0D80-\u0DFF]');
  static final _regexDevanagari = RegExp('[\u0900-\u097F]');
  static final _regexThai = RegExp('[\u0E00-\u0E7F\uF700-\uF70F]');
  static final _regexLaos = RegExp('[\u0E80-\u0EFF]');
  static final _regexKhmer = RegExp('[\u1780-\u17FF]');
  static final _regexBengali = RegExp('[\u0980-\u09FF]');
  static final _regexGurmukhi = RegExp('[\u0A00-\u0A7F]');
  static final _regexTaiTham = RegExp('[\u1A20-\u1AAF]');
  static final _regexGujarati = RegExp('[\u0A80-\u0AFF]');
  static final _regexTelegu = RegExp('[\u0C00-\u0C7F]');
  static final _regexKhannada = RegExp('[\u0C80-\u0CFF]');
  static final _regexMalayalam = RegExp('[\u0D00-\u0D7F]');
  // actual code block [0x11000, 0x1107F]
  // need check
  static final _regexBrahmi = RegExp('[\uD804\uDC00-\uDC7F]');
  static final _regexTibetan = RegExp('[\u0F00-\u0FFF]');
  // actual code block [0x11000, 0x1107F]
  //need check
  static final _regexCyrillic = RegExp('[\u0400-\u04FF\u0300-\u036F]');

  /// Whether the text holds any Roman letter, Pali or plain.
  static bool isRoman(String text) => text.contains(_regexRoman);

  static Script getLanguage(String scriptText) {
    if (scriptText.contains(_regexMM)) return Script.myanmar;
    if (scriptText.contains(_regexRoman)) return Script.roman;
    if (scriptText.contains(_regexSinhala)) return Script.sinhala;
    if (scriptText.contains(_regexDevanagari)) return Script.devanagari;
    if (scriptText.contains(_regexThai)) return Script.thai;
    if (scriptText.contains(_regexLaos)) return Script.laos;
    if (scriptText.contains(_regexKhmer)) return Script.khmer;
    if (scriptText.contains(_regexBengali)) return Script.bengali;
    if (scriptText.contains(_regexGurmukhi)) return Script.gurmukhi;
    if (scriptText.contains(_regexTaiTham)) return Script.taitham;
    if (scriptText.contains(_regexGujarati)) return Script.gujarati;
    if (scriptText.contains(_regexTelegu)) return Script.telugu;
    if (scriptText.contains(_regexKhannada)) return Script.kannada;
    if (scriptText.contains(_regexMalayalam)) return Script.malayalam;
    if (scriptText.contains(_regexBrahmi)) return Script.brahmi;
    if (scriptText.contains(_regexTibetan)) return Script.tibetan;
    if (scriptText.contains(_regexCyrillic)) return Script.cyrillic;
    // default
    return Script.roman;
  }
}
