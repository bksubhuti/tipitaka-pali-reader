// import to copy////////////////////
//import 'package:tipitaka_pali/services/prefs.dart';

// Shared prefs package import
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

// preference names
const String localeValPref = "localeVal";
const String themeIndexPref = "themeIndex";
const String darkThemeOnPref = "darkThemeOn";
const String fontSizePref = "fontSize";
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
const String animationSpeedPref = "animationSpeed";
const String selectedMainCategoryFiltersPref = "selectedMainCategoryFilters";
const String selectedSubCategoryFiltersPref = "selectedSubCategoryFilters";
const String tabsVisiblePref = "tabsVisible";

// default pref values
const int defaultLocaleVal = 0;
const int defaultThemeIndex = 24;
const bool defaultDarkThemeOn = false;
//ToDo something is not right with release and font size
const int defaultFontSize = 14;
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
const double defaultAnimationSpeed = 400;
const int defaultTabsVisible = 3;
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

  static bool get darkThemeOn =>
      instance.getBool(darkThemeOnPref) ?? defaultDarkThemeOn;
  static set darkThemeOn(bool value) =>
      instance.setBool(darkThemeOnPref, value);

  static int get fontSize => instance.getInt(fontSizePref) ?? defaultFontSize;
  static set fontSize(int value) => instance.setInt(fontSizePref, value);

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

  static int get selectedPageColor =>
      instance.getInt(selectedPageColorPref) ?? defaultSelectedPageColor;
  static set selectedPageColor(int value) =>
      instance.setInt(selectedPageColorPref, value);

  static String get databaseDirPath =>
      instance.getString(databaseDirPathPref) ?? defaultDatabaseDirPath;
  static set databaseDirPath(String value) =>
      instance.setString(databaseDirPathPref, value);

  static bool get saveClickToClipboard =>
      instance.getBool(saveClickToClipboardPref) ?? defaultSaveClickToClipboard;
  static set saveClickToClipboard(bool value) =>
      instance.setBool(saveClickToClipboardPref, value);

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
}
