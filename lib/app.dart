import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:tipitaka_pali/business_logic/models/bookmark.dart';
import 'package:tipitaka_pali/business_logic/models/tpr_message.dart';
import 'package:tipitaka_pali/business_logic/view_models/bookmark_page_view_model.dart';
import 'package:tipitaka_pali/providers/initial_setup_notifier.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/provider/user_notifier.dart';
import 'package:tipitaka_pali/ui/dialogs/show_tpr_message_dlg.dart';
import 'package:tipitaka_pali/ui/screens/home/openning_books_provider.dart';
import 'package:tipitaka_pali/unsupported_language_classes/ccp_intl.dart';
import 'package:tipitaka_pali/utils/platform_info.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/font_provider.dart';
import 'providers/navigation_provider.dart';
import 'routes.dart';
import 'services/provider/locale_change_notifier.dart';
import 'services/provider/script_language_provider.dart';
import 'services/provider/theme_change_notifier.dart';
import 'ui/screens/splash_screen.dart';
import 'package:tipitaka_pali/services/fetch_messages_if_needed.dart';
import 'package:app_links/app_links.dart';

final Logger myLogger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 5,
    lineLength: 50,
    colors: true,
    printEmojis: true,
    printTime: false,
  ),
  level: kDebugMode ? Level.all : Level.off,
);

class App extends StatefulWidget {
  final StreamingSharedPreferences rxPref;

  const App({required this.rxPref, super.key});

  @override
  _AppState createState() => _AppState();
}

class _AppState extends State<App> with WindowListener {
  StreamSubscription? _sub;
  // GlobalKey to access context for Dialogs/Navigation
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

//  AppLinks variables
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    // Register this class to listen to window events
    if (PlatformInfo.isDesktop) {
      windowManager.addListener(this);
    }
    _initDeepLinks(); // Call the function
  }

  @override
  void dispose() {
    // Clean up the listener
    if (PlatformInfo.isDesktop) {
      windowManager.removeListener(this);
    }
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    // Check for Cold Start
    final appLink = await _appLinks.getInitialLink();
    if (appLink != null) {
      print("Deep Link Received (Cold Start): $appLink"); // Debug Print
      _handleLink(appLink);
    }

    // Check for Foreground/Background
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      print("Deep Link Received (Stream): $uri"); // Debug Print
      _handleLink(uri);
    });
  }

  void _handleLink(Uri uri) {
    // 2. USE THE KEY to get the context.
    // This allows you to show a dialog from outside the widget tree.
    final context = _navigatorKey.currentContext;

    if (context != null) {
      // Small delay to ensure UI is ready
      Future.delayed(const Duration(milliseconds: 500), () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Deep Link Detected"),
            content: Text("Link: ${uri.toString()}"),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("OK"),
              ),
            ],
          ),
        );
      });
    } else {
      print("Context was null - could not show dialog");
    }
  }

  // 6. ADD: The Dialog Box
  void _showDeepLinkDialog(Uri uri) {
    // We use _navigatorKey.currentContext because the context of
    // _AppState is above the MaterialApp and cannot show Dialogs.
    final context = _navigatorKey.currentContext;

    if (context != null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Deep Link Detected"),
          content: Text("Link: ${uri.toString()}\nPath: ${uri.path}"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("OK"),
            ),
          ],
        ),
      );
    }
  }

  @override
  void onWindowResize() {
    // This triggers whenever the user drags the window edge
    if (PlatformInfo.isDesktop) {
      _saveWindowState();
    }
  }

  @override
  void onWindowMove() {
    // This triggers whenever the user drags the window header
    if (PlatformInfo.isDesktop) {
      _saveWindowState();
    }
  }

  Future<void> _saveWindowState() async {
    if (!PlatformInfo.isDesktop) return;
    // We use standard SharedPreferences here for simple key-value storage
    // You could use rxPref if you prefer, but this is cleaner for distinct window data.
    final bounds = await windowManager.getBounds();

    Prefs.windowWidth = bounds.width;
    Prefs.windowHeight = bounds.height;
    Prefs.windowX = bounds.topLeft.dx;
    Prefs.windowY = bounds.topLeft.dy;
  }

  @override
  Widget build(BuildContext context) {
    final modKey =
        Platform.isMacOS ? LogicalKeyboardKey.meta : LogicalKeyboardKey.control;
    return CallbackShortcuts(
        bindings: {
          SingleActivator(LogicalKeyboardKey.keyQ,
              meta: Platform.isMacOS ? true : false,
              control: Platform.isWindows || Platform.isLinux
                  ? true
                  : false): () => exit(0)
        },
        child: MultiProvider(
          providers: [
            Provider<StreamingSharedPreferences>.value(value: widget.rxPref),
            ChangeNotifierProvider<NavigationProvider>(
                create: (_) => NavigationProvider()),
            ChangeNotifierProvider<InitialSetupNotifier>(
                create: (_) => InitialSetupNotifier()),
            ChangeNotifierProvider<ThemeChangeNotifier>(
                create: (_) => ThemeChangeNotifier()),
            ChangeNotifierProvider<LocaleChangeNotifier>(
                create: (_) => LocaleChangeNotifier()),
            ChangeNotifierProvider<ScriptLanguageProvider>(
                create: (_) => ScriptLanguageProvider()),
            ChangeNotifierProvider<ReaderFontProvider>(
                create: (_) => ReaderFontProvider()),
            ChangeNotifierProvider<OpenningBooksProvider>(
                create: (_) => OpenningBooksProvider()),
            ChangeNotifierProvider<BookmarkPageViewModel>(
              create: (_) => BookmarkPageViewModel(),
              lazy: false,
            ),
            ChangeNotifierProvider<UserNotifier>(create: (_) => UserNotifier()),
          ],
          builder: (context, _) {
            final themeChangeNotifier = context.watch<ThemeChangeNotifier>();
            final localChangeNotifier = context.watch<LocaleChangeNotifier>();
            final scriptChangeNotifier =
                context.watch<ScriptLanguageProvider>();

            return MaterialApp(
              navigatorKey: _navigatorKey,
              debugShowCheckedModeBanner: false,
              themeMode: themeChangeNotifier.themeMode,
              theme: themeChangeNotifier.themeData,
              darkTheme: themeChangeNotifier.darkTheme,
              locale: Locale(localChangeNotifier.localeString, ''),
              onGenerateRoute: RouteGenerator.generateRoute,
              localizationsDelegates: const [
                CcpMaterialLocalizations.delegate,
                AppLocalizations.delegate,
                ...GlobalMaterialLocalizations.delegates,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [
                Locale('en', ''), // English, no country code
                Locale('my', ''), // Myanmar, no country code
                Locale('si', ''), // Sinahala, no country code
                Locale('zh', ''), // Chinese, no country code
                Locale('vi', ''), // Vietnamese, no country code
                Locale('hi', ''), // Hindi, no country code
                Locale('ru', ''), // Russian, no country code
                Locale('bn', ''), // Bengali, no country code
                Locale('km', ''), // khmer, no country code
                Locale('lo', ''), // Lao country code
                Locale('ccp'), // Chakma, no country code
                Locale('it', ''), // Italian, it
                Locale('th', ''), // Italian, it
              ],
              home: FutureBuilder(
                future: fetchMessageIfNeeded(),
                builder:
                    (BuildContext context, AsyncSnapshot<TprMessage> snapshot) {
                  //simulateFileOpen(context);

                  if (snapshot.connectionState == ConnectionState.done) {
                    if (snapshot.hasData &&
                        snapshot.data!.generalMessage.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        showWhatsNewDialog(context, snapshot.data!);
                      });
                    }
                  }

                  return SplashScreen();
                },
              ),
            );
          },
        ));
  }

  Future<void> simulateFileOpen(BuildContext context) async {
    try {
      // Simulate the URI of the file
/*      String basePath = await getDownloadFolderPath();
      String filePath = "$basePath/bookmarks.json";
      Uri mockUri = Uri.file(filePath);
      */
      await processFileUri(
        context,
      );
    } catch (e) {
      debugPrint("Error in simulateFileOpen: $e");
    }
  }

  Future<void> processFileUri(
    BuildContext context,
  ) async {
    try {
/*      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );


      File file = File(result!.paths.first ?? "");
*/

      File file = File("/home/bhante/Desktop/bookmarks.json");

      // Use this file to read content
      String content = await file.readAsString();
      List<Bookmark> importedBookmarks = bookmarkFromJson(content);

      if (importedBookmarks.isNotEmpty) {
        Bookmark bookmark = importedBookmarks.first;

        // Access the BookmarkViewModel from the context
        if (!context.mounted) return;
        final vm = context.read<BookmarkPageViewModel>();
        vm.openBook(bookmark, context);
      } else {
        debugPrint("json empty");
      }
    } catch (e) {
      debugPrint("Error processing the file: $e");
    }
  }

  Future<String> getDownloadFolderPath() async {
    final directory = await getExternalStorageDirectory();
    return "${directory!.path}/Download";
  }

  Future<File> getDownloadFile(String filename) async {
    // Path to the general Download directory
    String path = '/storage/emulated/0/Download';
    return File('$path/$filename');
  }

  Future<bool> requestStoragePermission() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    return status.isGranted;
  }
}
