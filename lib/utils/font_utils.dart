import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/utils/pali_script_converter.dart';

class FontUtils {
  FontUtils._();

  /// The font Pāḷi is drawn in, in [script]: the one chosen for that script
  /// in Settings › Theme, or else the one that comes with the app.
  static String? getfontName({required Script script}) {
    if (script != Script.roman) {
      final chosen = Prefs.scriptFontName(script.name);
      if (chosen.isNotEmpty) return chosen;
    }
    return defaultFontName(script);
  }

  /// The font that comes with the app for [script], or for Roman the one
  /// chosen from those.
  static String? defaultFontName(Script script) {
    switch (script) {
      case Script.myanmar:
        return 'PyidaungSu';
      case Script.sinhala:
        return 'NotoSansSinhala';
      case Script.devanagari:
        return 'NotoSansDevanagari';
      case Script.laos:
        return 'Lao Pali Regular';
      case Script.taitham:
        return 'NotoSansTaiTham';
      case Script.brahmi:
        return "Noto Sans Brahmi";
      case Script.roman:
        return (Prefs.romanFontName == 'System Font')
            ? null
            : Prefs.romanFontName;
      //return 'Langar';
      default:
        return null;
    }
  }

  /// The font for the app's menus: the one chosen in Settings › Theme, or
  /// else the one that goes with the app's language.
  static String? getfontNameByLocale({required String locale}) {
    final chosen = Prefs.appFontName;
    if (chosen.isNotEmpty) return chosen;
    return defaultAppFontName(locale);
  }

  static String? defaultAppFontName(String locale) {
    return switch (locale) {
      'en' => Prefs.romanFontName,
      //'en' => 'Langar',
      'my' => 'PyidaungSu',
      'si' => 'NotoSansSinhala',
      'hi' => 'NotoSansDevanagari',
      'lo' => 'Lao Pali Regular',
      'ccp' => 'NotoSans Chakma',
      _ => null,
    };
  }
}
