//import 'package:sqlite3/open.dart' as sqlite_open; // This will work now!
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:tipitaka_pali/app.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:devicelocale/devicelocale.dart';


import 'package:tipitaka_pali/services/setup_firestore.dart';
import 'package:tipitaka_pali/utils/platform_info.dart';
import 'package:window_manager/window_manager.dart';

// Global variable to store URL from command line.. vn bodhrasa
String? _initialUrl;
final ValueNotifier<String?> deepLinkNotifier = ValueNotifier(null);

void main(List<String> args) async {
  // Required for async calls in `main`
  WidgetsFlutterBinding.ensureInitialized();

  // If this returns false (because we are the second instance),
  // the app is already closed by now.
  if (Platform.isLinux || Platform.isWindows) {
    await ensureSingleInstance(args);
  }

  // Initialize SharedPrefs instance.
  await Prefs.init();

/*
  if (Platform.isWindows) {
    try {
      // 1. Force Dart to look for "sqlite3.dll" (the file you have)
      // instead of "sqlite3.x64.windows.dll" (the file it wants)
      sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.windows, () {
        return DynamicLibrary.open('sqlite3.dll');
      });
    } catch (e) {
      print("Could not load sqlite3.dll: $e");
    }
  }
   if (Platform.isLinux) {
    try {
      sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.linux, () {
        // Linux usually stores sqlite here
        return DynamicLibrary.open('libsqlite3.so.0');
      });
    } catch (e) {
      // If .so.0 fails, try just .so
      try {
        sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.linux, () {
          return DynamicLibrary.open('libsqlite3.so');
        });
      } catch (e) {
        print("Failed to load sqlite3: $e");
      }
    }
  }

  if (Platform.isMacOS) {
  sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.macOS, () {
    return DynamicLibrary.open('/usr/lib/libsqlite3.dylib');
  });
}
*/
  if (Platform.isWindows ||
      Platform.isLinux ||
      Platform.isMacOS ||
      Platform.isIOS ||
      Platform.isAndroid) {
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
    // no need twice.. it moved to tops
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
  await setupFirestore();

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
  runApp(App(
      rxPref: rxPref,
      initialUrl: _initialUrl,
      deepLinkNotifier: deepLinkNotifier));
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

Future<bool> ensureSingleInstance(List<String> args) async {
  const int appPort = 56789; // Unique port

  try {
    // Try to bind. If successful, we are the Main Instance.
    final serverSocket =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, appPort);

    // Listen for incoming links from future instances
    serverSocket.listen((Socket client) {
      client.listen((List<int> data) {
        final message = utf8.decode(data);
        if (message.isNotEmpty) {
          print("Received deep link from second instance: $message");

          // --- FIX: ACTUAL LOGIC CONNECTED HERE ---
          deepLinkNotifier.value = message;
          // ----------------------------------------
        }
      });
    });

    return true;
  } catch (e) {
    // Port is busy. We are the Second Instance.
    try {
      final socket =
          await Socket.connect(InternetAddress.loopbackIPv4, appPort);

      // Find the actual deep link in the args
      String message = 'focus';
      for (final arg in args) {
        if (arg.startsWith('tpr.pali.tools://')) {
          message = arg;
          break;
        }
      }

      socket.write(message);
      await socket.flush();
      socket.destroy();
    } catch (_) {}

    // Kill this second instance immediately
    exit(0);
  }
}
