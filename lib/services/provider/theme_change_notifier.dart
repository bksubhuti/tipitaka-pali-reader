import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:tipitaka_pali/data/flex_theme_data.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/provider/locale_change_notifier.dart';

import '../../utils/font_utils.dart';

class ThemeChangeNotifier extends ChangeNotifier {
  ThemeMode themeMode = (Prefs.darkThemeOn) ? ThemeMode.dark : ThemeMode.light;
  // ignore: unused_field
  int _themeIndex = 1;
  bool _useM3 = true;

  set useM3(bool val) {
    _useM3 = val;
    notifyListeners();
  }

  set themeIndex(int val) {
    _themeIndex = val;
    notifyListeners();
  }

  List<bool> get isSelected => List.generate(
        PageTheme.values.length,
        (i) => i == Prefs.selectedPageTheme.index,
      );

  bool get isDarkMode => themeMode == ThemeMode.dark;

  void toggleTheme(PageTheme theme) {
    Prefs.selectedPageTheme = theme;

    if (theme == PageTheme.dark) {
      themeMode = ThemeMode.dark;
      Prefs.darkThemeOn = true;
    } else {
      themeMode = ThemeMode.light;
      Prefs.darkThemeOn = false;
    }

    notifyListeners();
  }

  void onChangeFontSize(double fontSize) {
    Prefs.uiFontSize = fontSize;
    notifyListeners();
  }

  // --- Text Display Mode ---
  TextDisplayMode get textDisplayMode => Prefs.textDisplayMode;

  void onChangeTextDisplayMode(TextDisplayMode mode) {
    Prefs.textDisplayMode = mode;
    notifyListeners(); // This tells the Reader to refresh and hide/show text!
  }

  // --- Colors ---
  int get paliTextColor => Prefs.paliTextColor;

  void onChangePaliTextColor(int colorValue) {
    Prefs.paliTextColor = colorValue;
    notifyListeners(); // This tells the Reader to immediately repaint the Pali text!
  }

  int get translationColor => Prefs.translationColor;

  void onChangeTranslationColor(int colorValue) {
    Prefs.translationColor = colorValue;
    notifyListeners(); // This tells the Reader to immediately repaint the Translation text!
  }

  // Put this right near your textDisplayMode methods
  bool get isPaliBold => Prefs.isPaliBold;

  void onChangeIsPaliBold(bool isBold) {
    Prefs.isPaliBold = isBold;
    notifyListeners(); // Instantly updates the Reader view!
  }

  // Returns dark ThemeData made by FlexColorScheme
  ThemeData get darkTheme => FlexThemeData.dark(
        colors: myFlexSchemes[Prefs.themeIndex].dark,
        surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
        blendLevel: 2,
        tabBarStyle: FlexTabBarStyle.forAppBar,
        transparentStatusBar: true,
        subThemesData: FlexSubThemesData(
          appBarScrolledUnderElevation: Prefs.useM3 ? 6 : 0,
          blendOnLevel: 15,
          useTextTheme: true,
          useM2StyleDividerInM3: true,
          elevatedButtonSchemeColor: SchemeColor.onPrimaryContainer,
          elevatedButtonSecondarySchemeColor: SchemeColor.primaryContainer,
          inputDecoratorSchemeColor: SchemeColor.primary,
          inputDecoratorBackgroundAlpha: 28,
          inputDecoratorRadius: 8.0,
          inputDecoratorUnfocusedHasBorder: false,
          fabUseShape: true,
          fabAlwaysCircular: true,
          fabSchemeColor: SchemeColor.secondary,
          alignedDropdown: true,
          useInputDecoratorThemeInDialogs: true,
          drawerWidth: 300,
          tabBarIndicatorSize: TabBarIndicatorSize.tab,
          cardElevation: Prefs.useM3 ? 2 : 4,
          interactionEffects: true,
        ),
        keyColors: Prefs.useM3
            ? const FlexKeyColors(
                useSecondary: true,
                useTertiary: true,
                keepPrimary: true,
                keepSecondary: true,
                keepTertiary: true,
              )
            : null,
        tones: FlexTones.candyPop(Brightness.dark),
        visualDensity: FlexColorScheme.comfortablePlatformDensity,
        textTheme: _textTheme,
        useMaterial3: Prefs.useM3,
      ).copyWith(
        // Custom ExpansionTileTheme that removes the extra borders.
        expansionTileTheme: const ExpansionTileThemeData(
          shape: Border(),
          collapsedShape: Border(),
        ),
      );

  // Returns light ThemeData made by FlexColorScheme
  ThemeData get themeData => FlexThemeData.light(
        colors: myFlexSchemes[Prefs.themeIndex].light,
        surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
        blendLevel: 1,
        appBarStyle: Prefs.useM3 ? FlexAppBarStyle.surface : null,
        tabBarStyle: FlexTabBarStyle.forAppBar,
        transparentStatusBar: true,
        appBarElevation: Prefs.useM3 ? 3 : 0,
        subThemesData: FlexSubThemesData(
          appBarScrolledUnderElevation: Prefs.useM3 ? 6 : 0,
          blendOnLevel: 8,
          blendOnColors: false,
          useTextTheme: true,
          useM2StyleDividerInM3: true,
          elevatedButtonSchemeColor: SchemeColor.onPrimaryContainer,
          elevatedButtonSecondarySchemeColor: SchemeColor.primaryContainer,
          inputDecoratorSchemeColor: SchemeColor.primary,
          inputDecoratorBackgroundAlpha: 23,
          inputDecoratorRadius: 8.0,
          inputDecoratorUnfocusedHasBorder: false,
          fabUseShape: true,
          fabAlwaysCircular: true,
          fabSchemeColor: SchemeColor.secondary,
          alignedDropdown: true,
          useInputDecoratorThemeInDialogs: true,
          drawerWidth: 300,
          chipSelectedSchemeColor:
              Prefs.useM3 ? SchemeColor.primaryContainer : null,
          tabBarIndicatorSize: TabBarIndicatorSize.tab,
          cardElevation: Prefs.useM3 ? 2 : 4,
          interactionEffects: true,
        ),
        keyColors: Prefs.useM3
            ? const FlexKeyColors(
                useSecondary: true,
                useTertiary: true,
                keepPrimary: true,
                keepSecondary: true,
                keepTertiary: true,
              )
            : null,
        tones: FlexTones.candyPop(Brightness.light),
        visualDensity: FlexColorScheme.comfortablePlatformDensity,
        textTheme: _textTheme,
        useMaterial3: Prefs.useM3,
      ).copyWith(
        // Custom ExpansionTileTheme that removes the extra borders.
        expansionTileTheme: const ExpansionTileThemeData(
          shape: Border(),
          collapsedShape: Border(),
        ),
      );

  TextTheme get _textTheme {
    // this was changed for getting the laos font to work in the UI section of the
    // choose book screen.  However, it was decided not to support the Laos fonts unless
    // the copyright is properly expressed.
    // there seemed to be a little bit of a bug with going from lao script back to other scripts
    // if you did, you needed to restart the app.  To remedy this.. you can totally remove the code that
    // has the fontFamily for TextStyle parameter.

    // TODO need to follow up on lao font and test.
    final theFont = FontUtils.getfontNameByLocale(
        locale: LocaleChangeNotifier().localeString);

    return TextTheme(
      bodyLarge: TextStyle(
        fontSize: Prefs.uiFontSize + 2,
        fontWeight: FontWeight.w400,
        fontFamily: theFont, // passing the font name
      ),
      bodyMedium: TextStyle(
        fontSize: Prefs.uiFontSize,
        fontWeight: FontWeight.w400,
        fontFamily: theFont, // passing the font name
      ),
      bodySmall: TextStyle(
        fontSize: Prefs.uiFontSize - 3,
        fontWeight: FontWeight.w400,
        fontFamily: theFont, // passing the font name
      ),
      titleLarge: TextStyle(
        fontSize: Prefs.uiFontSize + 3,
        fontWeight: FontWeight.w600,
        fontFamily: theFont, // passing the font name
      ),
      titleMedium: TextStyle(
        fontSize: Prefs.uiFontSize + 2,
        fontWeight: FontWeight.w600,
        fontFamily: theFont, // passing the font name
      ),
      titleSmall: TextStyle(
        fontSize: Prefs.uiFontSize,
        fontWeight: FontWeight.w600,
        fontFamily: theFont, // passing the font name
      ),
    );
  }
}
