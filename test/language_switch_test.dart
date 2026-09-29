import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tipitaka_pali/services/language_installer.dart';
import 'package:tipitaka_pali/services/prefs.dart';

/// A translation can be on the device and switched off.
///
/// The distinction that matters: a language the reader turned off must stay
/// off, while one that has just appeared and was never offered should be
/// shown. From the file on disk those look identical, which is why the ones
/// already offered are remembered separately.
void main() {
  // Prefs.instance is late-final, so it is set once and the values are
  // cleared between tests instead.
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    Prefs.instance = await SharedPreferences.getInstance();
  });

  setUp(() {
    Prefs.activeLanguages = const [];
    Prefs.knownLanguages = const [];
  });

  test('installing a language shows it', () {
    LanguageInstaller.activate('en');
    expect(LanguageInstaller.isShown('en'), isTrue);
    expect(Prefs.knownLanguages, contains('en'));
  });

  test('switching off keeps the download', () {
    LanguageInstaller.activate('en');
    LanguageInstaller.setShown('en', false);

    expect(LanguageInstaller.isShown('en'), isFalse);
    expect(Prefs.knownLanguages, contains('en'),
        reason: 'off is not gone: the file stays, so turning it back on '
            'must not mean downloading it again');
  });

  test('switching back on restores it', () {
    LanguageInstaller.activate('en');
    LanguageInstaller.setShown('en', false);
    LanguageInstaller.setShown('en', true);
    expect(LanguageInstaller.isShown('en'), isTrue);
  });

  test('a second language is added rather than replacing the first', () {
    // The fault that made only English show: the first-run screen wrote a
    // list of one and nothing ever added to it.
    LanguageInstaller.activate('en');
    LanguageInstaller.activate('ru');
    expect(Prefs.activeLanguages, ['en', 'ru']);
  });

  test('switching one off and on again restores its place', () {
    LanguageInstaller.activate('en');
    LanguageInstaller.activate('ru');
    LanguageInstaller.setShown('en', false);
    expect(Prefs.activeLanguages, ['ru']);

    LanguageInstaller.setShown('en', true);
    expect(Prefs.activeLanguages, ['en', 'ru'],
        reason: 'it goes back where it was rather than onto the end, so '
            'turning a translation off to read the Pali alone does not '
            'rearrange the page when it comes back');
  });

  test('switching one off does not switch the others off', () {
    LanguageInstaller.activate('en');
    LanguageInstaller.activate('ru');
    LanguageInstaller.setShown('ru', false);
    expect(LanguageInstaller.isShown('en'), isTrue);
    expect(LanguageInstaller.isShown('ru'), isFalse);
  });

  test('switching all off leaves none shown', () {
    // The reader used to read an empty list as "show everything installed",
    // which would have made the last switch turn them all back on.
    LanguageInstaller.activate('en');
    LanguageInstaller.setShown('en', false);
    expect(Prefs.activeLanguages, isEmpty);
  });
}
