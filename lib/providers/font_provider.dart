import 'package:flutter/material.dart';

import '../services/language_installer.dart';
import '../services/prefs.dart';
import '../services/system_fonts.dart';
import '../utils/pali_script_converter.dart';

class ReaderFontProvider extends ChangeNotifier {
  late int _fontSize;
  int get fontSize => _fontSize;
  String? selectedFont =
      Prefs.romanFontName.isNotEmpty ? Prefs.romanFontName : 'Open Sans';

  /// The Roman fonts that come with the app, and the platform's own.
  static const List<String> bundledFonts = [
    'Open Sans',
    'Noto Serif',
    'DejaVu Sans',
    'System Font',
  ];

  ReaderFontProvider() {
    _init();
  }

  void _init() {
    _fontSize = Prefs.readerFontSize;
    // A font from the device is loaded again at each start. Until it is the
    // text shows in the platform's font; then it redraws in the chosen one.
    final files = Prefs.romanFontFiles;
    final family = selectedFont;
    if (files.isNotEmpty && family != null) {
      SystemFonts.load(family, files)
          .then((_) => notifyListeners(), onError: (_) {});
    }
    for (final script in Script.values) {
      final name = Prefs.scriptFontName(script.name);
      final files = Prefs.scriptFontFiles(script.name);
      if (name.isEmpty || files.isEmpty) continue;
      SystemFonts.load(name, files)
          .then((_) => notifyListeners(), onError: (_) {});
    }
    for (final language in LanguageInstaller.available) {
      final name = Prefs.translationFontName(language.code);
      final files = Prefs.translationFontFiles(language.code);
      if (name.isEmpty || files.isEmpty) continue;
      SystemFonts.load(name, files)
          .then((_) => notifyListeners(), onError: (_) {});
    }
  }

  /// Uses [family] for translations into [language], loading it first when
  /// it is one of the device's own fonts. Null goes back to the Pāḷi font.
  Future<void> chooseTranslationFont(String language, String? family,
      {List<String> files = const []}) async {
    if (family != null && files.isNotEmpty) {
      await SystemFonts.load(family, files);
    }
    Prefs.setTranslationFont(language, family ?? '', files);
    notifyListeners();
  }

  /// Uses [family] for Pāḷi in [script], loading it first when it is one of
  /// the device's own fonts. Null goes back to the one that comes with the
  /// app.
  Future<void> chooseScriptFont(Script script, String? family,
      {List<String> files = const []}) async {
    if (script == Script.roman) {
      return chooseFont(family ?? 'Open Sans', files: files);
    }
    if (family != null && files.isNotEmpty) {
      await SystemFonts.load(family, files);
    }
    Prefs.setScriptFont(script.name, family ?? '', files);
    notifyListeners();
  }

  void onIncreaseFontSize() {
    _fontSize += 1;
    Prefs.readerFontSize = _fontSize;
    notifyListeners();
  }

  void onDecreaseFontSize() {
    _fontSize -= 1;
    Prefs.readerFontSize = _fontSize;
    notifyListeners();
  }

  void setSelectedFont(String? newValue) {
    selectedFont = newValue;
    notifyListeners();
  }

  /// Uses [family] for Roman script, loading it first when it is one of the
  /// device's own fonts, from its [files].
  Future<void> chooseFont(String family,
      {List<String> files = const []}) async {
    if (files.isNotEmpty) await SystemFonts.load(family, files);
    Prefs.romanFontName = family;
    Prefs.romanFontFiles = files;
    setSelectedFont(family);
  }
}
