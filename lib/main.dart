import 'dart:ffi' as ffi;
import 'dart:ffi' show DynamicLibrary;
import 'package:sqlite3/common.dart' as sqlite_common;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:tipitaka_pali/app.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:devicelocale/devicelocale.dart';

import 'dart:io' show Platform;

import 'package:tipitaka_pali/services/setup_firestore.dart';
import 'package:tipitaka_pali/utils/platform_info.dart';
import 'package:window_manager/window_manager.dart';

// Global variable to store URL from command line.. vn bodhrasa
String? _initialUrl;

void main(List<String> args) async {
  // Required for async calls in `main`
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SharedPrefs instance.
  await Prefs.init();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    // Initialize FFI
    sqfliteFfiInit();

    // Change the default factory
    databaseFactory = databaseFactoryFfi;
  }

  if (Platform.isLinux || Platform.isWindows) {
    for (final arg in args) {
      if (arg.startsWith('tpr.pali.tools://')) {
        _initialUrl = arg;
        break;
      }
    }
  }

  if (PlatformInfo.isDesktop) {
    // Initialize window manager
    await windowManager.ensureInitialized();
    //Setup default window properties

    WindowOptions windowOptions = WindowOptions(
      size: Size(800, 600), // Fallback default size
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      // 2. Restore saved state
      await _restoreWindowBounds();

      // 3. Show the window gracefully
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // async calling of setup of firestore below
  setupFirestore();

  // This view is only called one time.
  // before the select language and before the select script are created
  // set the prefs to the current local if any OS but Win (not supported.)
  await setScriptAndLanguageByLocal();

  final info = await PackageInfo.fromPlatform();
  Prefs.versionNumber = '${info.version}+${info.buildNumber}';

  final rxPref = await StreamingSharedPreferences.instance;

  // check to see if we should have persistence with the search filter chips.
  // if not, (default), then we should reset the filter chips to all selected.
  // this prevents user from forgetting that they disabled many items and getting
  // empty searches.
  if (Prefs.persitentSearchFilter == false) {
    Prefs.selectedMainCategoryFilters = defaultSelectedMainCategoryFilters;
    Prefs.selectedSubCategoryFilters = defultSelectedSubCategoryFilters;
  }
  runApp(App(rxPref: rxPref, initialUrl: _initialUrl));
}

setScriptAndLanguageByLocal() async {
  final isExist = Prefs.isDatabaseSaved;
  // check for supported OS ..  mac linux ios android
  if (isExist == false) {
    // this is first time loading
    // now check for supported device for this package
    // all os but windows
    if (Platform.isWindows == false) {
      String? locale = await Devicelocale.currentLocale;
      if (locale != null) {
        //local first two letter.
        String shortLocale = locale.substring(0, 2);
        switch (shortLocale) {
          case "en":
            Prefs.localeVal = 0;
            Prefs.currentScriptLanguage = "ro";
            break;
          case "my":
            Prefs.localeVal = 1;
            Prefs.currentScriptLanguage = shortLocale;
            break;
          case "si":
            Prefs.localeVal = 2;
            Prefs.currentScriptLanguage = shortLocale;
            break;
          case "zh":
            Prefs.localeVal = 3;
            Prefs.currentScriptLanguage = "ro";
            break;
          case "vi":
            Prefs.localeVal = 4;
            Prefs.currentScriptLanguage = "ro";
            break;
          case "hi":
            Prefs.localeVal = 5;
            Prefs.currentScriptLanguage = shortLocale;
            break;
          case "ru":
            Prefs.localeVal = 6;
            Prefs.currentScriptLanguage = "ro";
            break;
          case "bn":
            Prefs.localeVal = 7;
            Prefs.currentScriptLanguage = shortLocale;
            break;
          case "km":
            Prefs.localeVal = 8;
            Prefs.currentScriptLanguage = shortLocale;
            break;
          case "lo":
            Prefs.localeVal = 9;
            Prefs.currentScriptLanguage = shortLocale;
            break;
          case "ccp":
            Prefs.localeVal = 10;
            Prefs.currentScriptLanguage = "ro";
            break;
          case "it":
            Prefs.localeVal = 11;
            Prefs.currentScriptLanguage = "ro";
            break;
          case "th":
            Prefs.localeVal = 12;
            Prefs.currentScriptLanguage = shortLocale;
            break;
        } // switch current local
      } // not null
    } // platform not windows
  } // first time loading
}

// Helper to restore bounds
Future<void> _restoreWindowBounds() async {
  // Check if we have saved data
  final double width = Prefs.windowWidth;
  final double height = Prefs.windowHeight;
  final double? x = Prefs.windowX;
  final double? y = Prefs.windowY;

  if (x != null && y != null) {
    // Set the bounds (position + size)
    await windowManager.setBounds(Rect.fromLTWH(x, y, width, height));
  }
}
