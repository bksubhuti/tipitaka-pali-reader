// import to copy////////////////////
//import 'package:tipitaka_pali/services/prefs.dart';

// Shared prefs package import

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tipitaka_pali/utils/simple_encryptor.dart';

import '../data/constants.dart';

enum PageTheme {
  light,
  medium,
  dark,
}

// preference names
const String localeValPref = "localeVal";
const String themeIndexPref = "themeIndex";
const String themeNamePref = "themeNamePref";
const String darkThemeOnPref = "darkThemeOn";
const String readerFontSizePref = "fontSize";
const String uiFontSizePref = "ui_fontSize";
const String dictionaryFontSizePref = "dictionaryFontSize";
const String databaseVersionPref = "databaseVersion";
const String isDatabaseSavedPref = "isDatabaseSaved";
const String isShowAlternatePaliPref = 'showAlternatePali';
const String isShowPtsNumberPref = 'showPtsNumber';
const String isShowThaiNumberPref = 'showThaiNumber';
const String isShowVriNumberPref = 'showVriNumber';
const String currentScriptLocaleCodePref = 'currentScriptLocaleCode';
const String queryModePref = 'queryMode';
const String wordDistancePref = 'wordDistance';
const String isPeuPref = "isPeuOn";
const String isDpdPref = "isDpdOn";
const String selectedPageColorPref = "selectedPageColor";
const String databaseDirPathPref = "databaseDirPath";
const String saveClickToClipboardPref = "saveClickToClipbard";
const String multiTabModePref = "multiTabMode";
const String animationSpeedPref = "animationSpeed";
const String selectedMainCategoryFiltersPref = "selectedMainCategoryFilters";
const String selectedSubCategoryFiltersPref = "selectedSubCategoryFilters";
const String tabsVisiblePref = "tabsVisible";
const String controlBarShowPref = "controlBarShow";
const String isFuzzyPref = "isFuzzy";
const String newTabAtEnd = 'newTabAtEnd';
const String isDpdGrammarOnPref = "isDpdGrammarOn";
const String alwaysShowDpdSplitterPref = "alwasyShowDpdSplitter";
const String numberBooksOpenedPref = "numberBooksOpened";
const String numberWordsLookedUpPref = "numberWordsLookedUp";
const String okToRatePref = "okToRate";
const String multiHighlightPref = "singleHighlight";
const String expandedBookListPref = "expandedBookList";
const String messagePref = "message";
const String messageDatePref = "messageDate";
const String lastDateCheckedMessagePref = "lastDateCheckedMessage";
const String showWhatsNewPref = "dontShowMessage";
const String versionNumberPref = "versionNumber";
const String keyBookViewModeIndex = 'book_view_mode';
const String emailPref = 'username';
const String passwordPref = 'password';
const String isSignedInPref = 'isSignedIn'; // true if user is signed in
const String lastSyncDatePref = 'lastSyncDate';
const String disableVelthuisPref = 'disableVelthuis';
const String persitentSearchFilterPref = 'persistentSearchFilter';
const String useM3Pref = 'useM3';
const String romanFontNamePref = "romanFontName";
const String oldPasswordPref = 'oldPassword';
const String oldUsernamePref = 'oldUsername';
const String hideScrollbarPref = 'hideScrollbar';
const String hideIPAPref = 'hideIPA';
const String hideSanskritPref = 'hideSanskrit';
const String panelWidthKey = 'panelWidth';
const String openRouterApiKeyPref = "openRouterApiKey";
const String openRouterPromptPref = 'openRouterPrompt';
const String openRouterModelPref = 'openRouterModel';
const String openRouterPromptKeyPref = 'openRouterPromptKey';
const String useGeminiDirectPref = 'useGeminiDirect';
const String geminiDirectApiKeyPref = 'geminiDirectApiKey';
const String windowWidthPref = "windowWidth";
const String windowHeightPref = "windowHeight";
const String windowXPref = "windowX";
const String windowYPref = "windowY";

// default pref values
const int defaultLocaleVal = 0;
const int defaultThemeIndex = 12;
const String defaultThemeName = '';

const bool defaultDarkThemeOn = false;
//ToDo something is not right with release and font size
const int defaultReaderFontSize = 14;
const double defaultUiFontSize = 14.0;
const int defaultDictionaryFontSize = 14;
const int defaultDatabaseVersion = 1;
const bool defaultIsDatabaseSaved = false;
const bool defaultShowAlternatePali = false;
const bool defaultShowPTSNumber = false;
const bool defaultShowThaiNumber = false;
const bool defaultShowVRINumber = false;
const String defaultScriptLanguage = 'ro';
const int defaultQueryModeIndex = 0;
const int defaultWordDistance = 10;
const bool defaultIsPeuOn = true;
const bool defaultIsDpdOn = true;
int defaultSelectedPageColor = 0;
const String defaultDatabaseDirPath = "";
const bool defaultSaveClickToClipboard = false;
const bool defaultmultiTabMode = false;
const double defaultAnimationSpeed = 400;
const int defaultTabsVisible = 3;
const bool defaultControlBarShow = true;
const bool defaultIsFuzzy = true;
const bool defaultNewTabAtEnd = false;
const bool defaultIsDpdGrammarOn = false;
const bool defaultAlwaysShowDpdSplitter = true;
const int defaultNumberBooksOpened = 0;
const int defaultNumberWordsLookedUp = 0;
const bool defaultOkToRate = true;
const bool defaultMultiHighlight = false;
const bool defaultExpandedBookList = false;
const String defaultMessage = "";
const String defaultMessageDate = "20230701";
const String defaultLastDateCheckedMessage = "20230701";
const bool defaultShowWhatsNew = true;
const String defaultVersionNumber = "2.3.4+53";
const int defaultBookViewMode = 0; // horizontal
const String defaultEmail = '';
const String defaultPassword = '';
const bool defaultIsSignedIn = false;
const String defaltLastSyncDate = '197001010000';
const bool defaultDisableVelthuis = false;
const bool defaultPersitentSearchFilter = false;
const bool defaultUseM3 = true;
const String defaultRomanFontName = "Open Sans";
const String defaultOldPassword = '';
const String defaultOldUsername = '';
const bool defaultHideScrollbar = false;
const bool defaultHideIPA = true;
const bool defaultHideSanskrit = true;
const double defaultPanelWidth = 350;
const String defaultOpenRouterPromptKey = 'line_by_line';
const String defaultOpenRouterApiKey = "";
const double defaultWindowWidth = 1000.0;
const double defaultWindowHeight = 800.0;
const String defaultOpenRouterPrompt = """
Translate the following Pāḷi into clean, readable HTML.
Translate sentence by sentence.
Use <b> for Pāḷi line and <br> to separate lines. Normal text for English. Do not translate common terms like Nibbāna, mettā, or dukkha.
Output only HTML. Do not explain.
""";
const String defaultOpenRouterModel = "google/gemini-2.5-pro-exp-03-25:free";

List<String> defaultSelectedMainCategoryFilters = [
  "mula",
  "annya",
  "attha",
  "tika"
];
List<String> defultSelectedSubCategoryFilters = [
  "_vi",
  "_di",
  "_ma",
  "_sa",
  "_an",
  "_ku",
  "_bi",
  "_pe"
];

class Prefs {
  // prevent object creation
  Prefs._();
  static late final SharedPreferences instance;

  static Future<SharedPreferences> init() async =>
      instance = await SharedPreferences.getInstance();

  // get and set the default member values if null
  static int get localeVal =>
      instance.getInt(localeValPref) ?? defaultLocaleVal;
  static set localeVal(int value) => instance.setInt(localeValPref, value);

  static int get themeIndex =>
      instance.getInt(themeIndexPref) ?? defaultThemeIndex;
  static set themeIndex(int value) => instance.setInt(themeIndexPref, value);

  static String get themeName =>
      instance.getString(themeNamePref) ?? defaultThemeName;
  static set themeName(String value) =>
      instance.setString(themeNamePref, value);

  static bool get darkThemeOn =>
      instance.getBool(darkThemeOnPref) ?? defaultDarkThemeOn;
  static set darkThemeOn(bool value) =>
      instance.setBool(darkThemeOnPref, value);

  static int get readerFontSize =>
      instance.getInt(readerFontSizePref) ?? defaultReaderFontSize;
  static set readerFontSize(int value) =>
      instance.setInt(readerFontSizePref, value);

  static double get uiFontSize =>
      instance.getDouble(uiFontSizePref) ?? defaultUiFontSize;
  static set uiFontSize(double value) =>
      instance.setDouble(uiFontSizePref, value);

  static int get dictionaryFontSize =>
      instance.getInt(dictionaryFontSizePref) ?? defaultDictionaryFontSize;
  static set dictionaryFontSize(int value) =>
      instance.setInt(dictionaryFontSizePref, value);

  static int get databaseVersion =>
      instance.getInt(databaseVersionPref) ?? defaultDatabaseVersion;
  static set databaseVersion(int value) =>
      instance.setInt(databaseVersionPref, value);

  static bool get isDatabaseSaved =>
      instance.getBool(isDatabaseSavedPref) ?? defaultIsDatabaseSaved;
  static set isDatabaseSaved(bool value) =>
      instance.setBool(isDatabaseSavedPref, value);

  static bool get isShowAlternatePali =>
      instance.getBool(isShowAlternatePaliPref) ?? defaultShowAlternatePali;
  static set isShowAlternatePali(bool value) =>
      instance.setBool(isShowAlternatePaliPref, value);

  static bool get isShowPtsNumber =>
      instance.getBool(isShowPtsNumberPref) ?? defaultShowPTSNumber;
  static set isShowPtsNumber(bool value) =>
      instance.setBool(isShowPtsNumberPref, value);

  static bool get isShowThaiNumber =>
      instance.getBool(isShowThaiNumberPref) ?? defaultShowThaiNumber;
  static set isShowThaiNumber(bool value) =>
      instance.setBool(isShowThaiNumberPref, value);

  static bool get isShowVriNumber =>
      instance.getBool(isShowVriNumberPref) ?? defaultShowVRINumber;
  static set isShowVriNumber(bool value) =>
      instance.setBool(isShowVriNumberPref, value);

  static String get currentScriptLanguage =>
      instance.getString(currentScriptLocaleCodePref) ?? defaultScriptLanguage;
  static set currentScriptLanguage(String value) =>
      instance.setString(currentScriptLocaleCodePref, value);

  static int get queryModeIndex =>
      instance.getInt(queryModePref) ?? defaultQueryModeIndex;
  static set queryModeIndex(int value) => instance.setInt(queryModePref, value);

  static int get wordDistance =>
      instance.getInt(wordDistancePref) ?? defaultWordDistance;
  static set wordDistance(int value) =>
      instance.setInt(wordDistancePref, value);

  static bool get isPeuOn => instance.getBool(isPeuPref) ?? defaultIsPeuOn;
  static set isPeuOn(bool value) => instance.setBool(isPeuPref, value);

  static bool get isDpdOn => instance.getBool(isDpdPref) ?? defaultIsDpdOn;
  static set isDpdOn(bool value) => instance.setBool(isDpdPref, value);

  static PageTheme get selectedPageTheme =>
      PageTheme.values[instance.getInt(selectedPageColorPref) ?? 0];

  static set selectedPageTheme(PageTheme theme) =>
      instance.setInt(selectedPageColorPref, theme.index);

  static String get databaseDirPath =>
      instance.getString(databaseDirPathPref) ?? defaultDatabaseDirPath;
  static set databaseDirPath(String value) =>
      instance.setString(databaseDirPathPref, value);

  static bool get saveClickToClipboard =>
      instance.getBool(saveClickToClipboardPref) ?? defaultSaveClickToClipboard;
  static set saveClickToClipboard(bool value) =>
      instance.setBool(saveClickToClipboardPref, value);

  static bool get multiTabMode =>
      instance.getBool(multiTabModePref) ?? defaultmultiTabMode;
  static set multiTabMode(bool value) =>
      instance.setBool(multiTabModePref, value);

  static double get animationSpeed =>
      instance.getDouble(animationSpeedPref) ?? defaultAnimationSpeed;
  static set animationSpeed(double value) =>
      instance.setDouble(animationSpeedPref, value);

  static List<String> get selectedMainCategoryFilters =>
      instance.getStringList(selectedMainCategoryFiltersPref) ??
      defaultSelectedMainCategoryFilters;
  static set selectedMainCategoryFilters(List<String> value) =>
      instance.setStringList(selectedMainCategoryFiltersPref, value);

  static List<String> get selectedSubCategoryFilters =>
      instance.getStringList(selectedSubCategoryFiltersPref) ??
      defultSelectedSubCategoryFilters;
  static set selectedSubCategoryFilters(List<String> value) =>
      instance.setStringList(selectedSubCategoryFiltersPref, value);

  static int get tabsVisible =>
      instance.getInt(tabsVisiblePref) ?? defaultTabsVisible;
  static set tabsVisible(int value) => instance.setInt(tabsVisiblePref, value);

  static bool get controlBarShow =>
      instance.getBool(controlBarShowPref) ?? defaultControlBarShow;
  static set controlBarShow(bool value) =>
      instance.setBool(controlBarShowPref, value);

  static bool get isFuzzy => instance.getBool(isFuzzyPref) ?? defaultIsFuzzy;
  static set isFuzzy(bool value) => instance.setBool(isFuzzyPref, value);

  static bool get isNewTabAtEnd =>
      instance.getBool(newTabAtEnd) ?? defaultNewTabAtEnd;
  static set isNewTabAtEnd(bool value) => instance.setBool(newTabAtEnd, value);

  static bool get isDpdGrammarOn =>
      instance.getBool(isDpdGrammarOnPref) ?? defaultIsDpdGrammarOn;
  static set isDpdGrammarOn(bool value) =>
      instance.setBool(isDpdGrammarOnPref, value);

  static bool get alwaysShowDpdSplitter =>
      instance.getBool(alwaysShowDpdSplitterPref) ??
      defaultAlwaysShowDpdSplitter;
  static set alwaysShowDpdSplitter(bool value) =>
      instance.setBool(alwaysShowDpdSplitterPref, value);

  // Get and set the default member values if null
  static int get numberBooksOpened =>
      instance.getInt(numberBooksOpenedPref) ?? defaultNumberBooksOpened;

  static set numberBooksOpened(int value) =>
      instance.setInt(numberBooksOpenedPref, value);

  static int get numberWordsLookedUp =>
      instance.getInt(numberWordsLookedUpPref) ?? defaultNumberWordsLookedUp;

  static set numberWordsLookedUp(int value) =>
      instance.setInt(numberWordsLookedUpPref, value);

  static bool get okToRate => instance.getBool(okToRatePref) ?? defaultOkToRate;

  static set okToRate(bool value) => instance.setBool(okToRatePref, value);

  // Add getter and setter for singleHighlight
  static bool get multiHighlight =>
      instance.getBool(multiHighlightPref) ?? defaultMultiHighlight;
  static set multiHighlight(bool value) =>
      instance.setBool(multiHighlightPref, value);

  static bool get expandedBookList =>
      instance.getBool(expandedBookListPref) ?? defaultExpandedBookList;
  static set expandedBookList(bool value) =>
      instance.setBool(expandedBookListPref, value);

  static String get message =>
      instance.getString(messagePref) ?? defaultMessage;
  static set message(String value) => instance.setString(messagePref, value);

  static String get messageDate =>
      instance.getString(messageDatePref) ?? defaultMessageDate;
  static set messageDate(String value) =>
      instance.setString(messageDatePref, value);

  static String get lastDateCheckedMessage =>
      instance.getString(lastDateCheckedMessagePref) ??
      defaultLastDateCheckedMessage;
  static set lastDateCheckedMessage(String value) =>
      instance.setString(lastDateCheckedMessagePref, value);

  static bool get showWhatsNew =>
      instance.getBool(showWhatsNewPref) ?? defaultShowWhatsNew;
  static set showWhatsNew(bool value) =>
      instance.setBool(showWhatsNewPref, value);

  static String get versionNumber =>
      instance.getString(versionNumberPref) ?? defaultVersionNumber;
  static set versionNumber(String value) =>
      instance.setString(versionNumberPref, value);

  static String get email => instance.getString(emailPref) ?? defaultEmail;
  static set email(String value) => instance.setString(emailPref, value);

  static String get password =>
      instance.getString(passwordPref) ?? defaultPassword;
  static set password(String value) => instance.setString(passwordPref, value);

  static bool get isSignedIn =>
      instance.getBool(isSignedInPref) ?? defaultIsSignedIn;
  static set isSignedIn(bool value) => instance.setBool(isSignedInPref, value);

  static String get lastSyncDate =>
      instance.getString(lastSyncDatePref) ?? defaltLastSyncDate;
  static set lastSyncDate(String value) =>
      instance.setString(lastSyncDatePref, value);

  static bool get disableVelthuis =>
      instance.getBool(disableVelthuisPref) ?? defaultDisableVelthuis;
  static set disableVelthuis(bool value) =>
      instance.setBool(disableVelthuisPref, value);

  static bool get persitentSearchFilter =>
      instance.getBool(persitentSearchFilterPref) ??
      defaultPersitentSearchFilter;
  static set persitentSearchFilter(bool value) =>
      instance.setBool(persitentSearchFilterPref, value);

  static bool get useM3 => instance.getBool(useM3Pref) ?? defaultUseM3;
  static set useM3(bool value) => instance.setBool(useM3Pref, value);

  static String get romanFontName =>
      instance.getString(romanFontNamePref) ?? defaultRomanFontName;
  static set romanFontName(String value) =>
      instance.setString(romanFontNamePref, value);

  static String get oldPassword =>
      instance.getString(oldPasswordPref) ?? defaultOldPassword;
  static set oldPassword(String value) =>
      instance.setString(oldPasswordPref, value);

  static String get oldUsername =>
      instance.getString(oldUsernamePref) ?? defaultOldUsername;
  static set oldUsername(String value) =>
      instance.setString(oldUsernamePref, value);

  static bool get hideIPA => instance.getBool(hideIPAPref) ?? defaultHideIPA;
  static set hideIPA(bool value) => instance.setBool(hideIPAPref, value);

  static bool get hideSanskrit =>
      instance.getBool(hideSanskritPref) ?? defaultHideSanskrit;
  static set hideSanskrit(bool value) =>
      instance.setBool(hideSanskritPref, value);

// openRouter ai stuff
// encrypted is hidden from other callers.
  static String get openRouterApiKey {
    final encrypted = instance.getString(openRouterApiKeyPref);
    if (encrypted == null || encrypted.isEmpty) return '';
    return SimpleEncryptor("ai_secret_key_2025").decryptText(encrypted);
  }

  static set openRouterApiKey(String value) {
    final encrypted = SimpleEncryptor("ai_secret_key_2025").encryptText(value);
    instance.setString(openRouterApiKeyPref, encrypted);
  }

  static String get openRouterPrompt =>
      instance.getString(openRouterPromptPref) ?? defaultOpenRouterPrompt;

  static set openRouterPrompt(String value) =>
      instance.setString(openRouterPromptPref, value);

  static String get openRouterModel =>
      instance.getString(openRouterModelPref) ?? defaultOpenRouterModel;

  static set openRouterModel(String value) =>
      instance.setString(openRouterModelPref, value);

  static String get openRouterPromptKey =>
      instance.getString(openRouterPromptKeyPref) ?? defaultOpenRouterPromptKey;

  static set openRouterPromptKey(String value) =>
      instance.setString(openRouterPromptKeyPref, value);

  static bool get useGeminiDirect =>
      instance.getBool(useGeminiDirectPref) ?? false;
  static set useGeminiDirect(bool value) =>
      instance.setBool(useGeminiDirectPref, value);

  static String get geminiDirectApiKey =>
      instance.getString(geminiDirectApiKeyPref) ?? '';
  static set geminiDirectApiKey(String value) =>
      instance.setString(geminiDirectApiKeyPref, value);

  // Window Size and Position
  static double get windowWidth =>
      instance.getDouble(windowWidthPref) ?? defaultWindowWidth;
  static set windowWidth(double value) =>
      instance.setDouble(windowWidthPref, value);

  static double get windowHeight =>
      instance.getDouble(windowHeightPref) ?? defaultWindowHeight;
  static set windowHeight(double value) =>
      instance.setDouble(windowHeightPref, value);

  // We return nullable double? for X and Y.
  // If null, the window manager will know to center the window default.
  static double? get windowX => instance.getDouble(windowXPref);
  static set windowX(double? value) =>
      instance.setDouble(windowXPref, value ?? 0.0);

  static double? get windowY => instance.getDouble(windowYPref);
  static set windowY(double? value) =>
      instance.setDouble(windowYPref, value ?? 0.0);

  // ===========================================================================
  // Helpers

  static Color getChosenColor(BuildContext context) {
    switch (Prefs.selectedPageTheme) {
      case PageTheme.light:
        return Colors.white;
      case PageTheme.medium:
        return Theme.of(context).colorScheme.surfaceContainer;
      case PageTheme.dark:
        return Colors.black;
    }
  }

  static bool isUsageAttained() {
    return (numberBooksOpened > maxBooksOpened &&
            numberWordsLookedUp > maxWordsLookedUp) &&
        okToRate;
  }

  static int get bookViewModeIndex =>
      instance.getInt(keyBookViewModeIndex) ?? defaultBookViewMode;

  static set bookViewModeIndex(int value) =>
      instance.setInt(keyBookViewModeIndex, value);

  static double get panelWidth =>
      instance.getDouble(panelWidthKey) ?? defaultPanelWidth;
  static set panelWidth(double value) =>
      instance.setDouble(panelWidthKey, value);
}
