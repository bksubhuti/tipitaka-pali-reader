import 'package:flutter/foundation.dart';

import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/language_installer.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/provider/theme_change_notifier.dart';

/// Which languages the reader shows: Pali, and each installed translation.
///
/// Two preferences carry this between them. The text display mode decides
/// whether the Pali and the translations are shown at all, and is applied
/// when a page is drawn, so changing it is instant. The list of shown
/// languages decides which translations are put into the page when it is
/// composed, so changing it means the open books compose their pages again.
/// [version] moves when that happens, and an open reader reloads on it.
///
/// Read together, the two give one switch per language:
///
///   * Pali is shown unless the mode is translation only;
///   * a translation is shown if it is in the list and the mode is not Pali
///     only.
///
/// Something always stays on. A reader cannot switch off the last thing
/// showing and be left with an empty page.
class ShownLanguagesProvider extends ChangeNotifier {
  final ThemeChangeNotifier _theme;

  ShownLanguagesProvider(this._theme);

  /// Moves whenever the set of translations composed into pages changes.
  int get version => _version;
  int _version = 0;

  /// Installed translations, in the reader's chosen order.
  List<String> get installed {
    final present = DatabaseHelper.installedLanguages;
    final order = Prefs.knownLanguages.where(present.contains).toList();
    for (final code in present) {
      if (!order.contains(code)) order.add(code);
    }
    return order;
  }

  TextDisplayMode get _mode => Prefs.textDisplayMode;

  bool isShown(String code) =>
      _mode != TextDisplayMode.paliOnly &&
      Prefs.activeLanguages.contains(code) &&
      DatabaseHelper.installedLanguages.contains(code);

  List<String> get shownLanguages => installed.where(isShown).toList();

  /// The Pali is shown unless a translation is shown in its place. With no
  /// translation showing it is always on, whatever the mode says.
  bool get paliShown =>
      _mode != TextDisplayMode.translationOnly || shownLanguages.isEmpty;

  int get _shownCount => (paliShown ? 1 : 0) + shownLanguages.length;

  /// Whether the Pali switch may be turned off: only with a translation on.
  bool get canHidePali => !paliShown || shownLanguages.isNotEmpty;

  /// Whether [code] may be turned off without leaving nothing on screen.
  bool canHide(String code) => !isShown(code) || _shownCount > 1;

  void setPaliShown(bool on) {
    if (!on && !canHidePali) return;
    _setMode(paliOn: on, languagesOn: shownLanguages.isNotEmpty);
  }

  void setLanguageShown(String code, bool on) {
    if (on == isShown(code)) return;
    if (!on && !canHide(code)) return;

    if (on && _mode == TextDisplayMode.paliOnly) {
      // Pali only hid every translation in the list without taking it out.
      // Turning one on shows that one, not all of them at once.
      Prefs.activeLanguages = const [];
    }
    LanguageInstaller.setShown(code, on);

    final languagesOn = shownLanguagesIgnoringMode.isNotEmpty;
    // Turning off the last translation brings the Pali back if it was off.
    _setMode(paliOn: paliShown || !languagesOn, languagesOn: languagesOn);
    _version++;
    notifyListeners();
  }

  /// The translations in the list, as they will be once the mode allows them.
  List<String> get shownLanguagesIgnoringMode => installed
      .where((c) => Prefs.activeLanguages.contains(c))
      .toList();

  /// Called after a language is installed or removed, so open books pick it
  /// up without a restart.
  void installedChanged() {
    final languagesOn = shownLanguagesIgnoringMode.isNotEmpty;
    if (!languagesOn && _mode == TextDisplayMode.translationOnly) {
      _setMode(paliOn: true, languagesOn: false);
    } else if (languagesOn && _mode == TextDisplayMode.paliOnly) {
      // Installing a language is asking to see it.
      _setMode(paliOn: true, languagesOn: true);
    }
    _version++;
    notifyListeners();
  }

  /// Rearranges the shown order; the pages compose again in the new order.
  void reordered() {
    _version++;
    notifyListeners();
  }

  void _setMode({required bool paliOn, required bool languagesOn}) {
    final TextDisplayMode mode;
    if (!languagesOn) {
      mode = TextDisplayMode.paliOnly;
    } else if (paliOn) {
      mode = TextDisplayMode.paliAndTranslation;
    } else {
      mode = TextDisplayMode.translationOnly;
    }
    if (mode != _mode) {
      _theme.onChangeTextDisplayMode(mode);
    }
    notifyListeners();
  }
}
