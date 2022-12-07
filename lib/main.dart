import 'package:flutter/material.dart';
import 'app.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'package:devicelocale/devicelocale.dart';

import 'dart:io' show Platform;

void main() async {
  if (Platform.isWindows || Platform.isLinux) {
    // Initialize FFI
    sqfliteFfiInit();

    // Change the default factory
    databaseFactory = databaseFactoryFfi;
  }

  // Required for async calls in `main`
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize SharedPrefs instance.
  await Prefs.init();

  // This view is only called one time.
  // before the select language and before the select script are created
  // set the prefs to the current local if any OS but Win (not supported.)
  await setScriptAndLanguageByLocal();

  runApp(const App());
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
          // TODO: need to add enum for the localeVal
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
        } // switch current local
      } // not null
    } // platform not windows
  } // first time loading
}
