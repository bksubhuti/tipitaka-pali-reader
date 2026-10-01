import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/provider/shown_languages_provider.dart';
import 'package:tipitaka_pali/services/provider/theme_change_notifier.dart';

/// One switch for the Pali and one per translation, read off two preferences.
///
/// What matters: something always stays on, a switch shows what the page
/// shows, and only a change to which translations are composed asks the open
/// books to reload — a change of display mode is drawn without one.
void main() {
  late ShownLanguagesProvider shown;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    Prefs.instance = await SharedPreferences.getInstance();
  });

  setUp(() {
    DatabaseHelper.installedLanguages = ['en', 'my'];
    Prefs.knownLanguages = ['en', 'my'];
    Prefs.activeLanguages = ['en'];
    Prefs.textDisplayMode = TextDisplayMode.paliAndTranslation;
    shown = ShownLanguagesProvider(ThemeChangeNotifier());
  });

  tearDown(() => DatabaseHelper.installedLanguages = const []);

  test('the switches read what the page shows', () {
    expect(shown.paliShown, isTrue);
    expect(shown.isShown('en'), isTrue);
    expect(shown.isShown('my'), isFalse);
  });

  test('turning a second language on reloads books and shows both', () {
    final before = shown.version;
    shown.setLanguageShown('my', true);
    expect(shown.shownLanguages, ['en', 'my']);
    expect(shown.version, greaterThan(before));
  });

  test('Pali can go off only while a translation is on', () {
    final before = shown.version;
    shown.setPaliShown(false);
    expect(shown.paliShown, isFalse);
    expect(Prefs.textDisplayMode, TextDisplayMode.translationOnly);
    expect(shown.version, before, reason: 'drawn, not recomposed');

    expect(shown.canHide('en'), isFalse, reason: 'the last thing showing');
    shown.setLanguageShown('en', false);
    expect(shown.isShown('en'), isTrue);
  });

  test('turning off the last translation leaves the Pali on', () {
    shown.setLanguageShown('en', false);
    expect(shown.shownLanguages, isEmpty);
    expect(shown.paliShown, isTrue);
    expect(shown.canHidePali, isFalse);
    shown.setPaliShown(false);
    expect(shown.paliShown, isTrue);
  });

  test('from Pali only, turning one on shows that one alone', () {
    Prefs.activeLanguages = ['en', 'my'];
    Prefs.textDisplayMode = TextDisplayMode.paliOnly;
    expect(shown.shownLanguages, isEmpty);

    shown.setLanguageShown('my', true);
    expect(shown.shownLanguages, ['my']);
    expect(shown.paliShown, isTrue);
  });

  test('with nothing installed the Pali cannot be switched off', () {
    DatabaseHelper.installedLanguages = const [];
    expect(shown.installed, isEmpty);
    expect(shown.paliShown, isTrue);
    expect(shown.canHidePali, isFalse);
  });

  test('an install shows the language even from Pali only', () {
    Prefs.activeLanguages = const [];
    Prefs.textDisplayMode = TextDisplayMode.paliOnly;
    Prefs.activeLanguages = ['my'];
    final before = shown.version;
    shown.installedChanged();
    expect(shown.shownLanguages, ['my']);
    expect(shown.version, greaterThan(before));
  });
}
