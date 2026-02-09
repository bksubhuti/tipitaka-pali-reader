import 'package:flutter/material.dart';
import 'package:tipitaka_pali/ui/dialogs/extension_prompt_dialog.dart';
import 'package:tipitaka_pali/ui/screens/dictionary/dictionary_page.dart';
import 'package:tipitaka_pali/ui/screens/dictionary/text_converter_view.dart';
import 'package:tipitaka_pali/ui/screens/home/home_container.dart';
import 'package:tipitaka_pali/ui/screens/home/search_page/search_page.dart';
import 'package:tipitaka_pali/ui/screens/reader/reader.dart';
import 'package:tipitaka_pali/ui/screens/search_result/search_result_page.dart';
import 'package:tipitaka_pali/ui/screens/settings/book_import_view.dart';
import 'package:tipitaka_pali/ui/screens/settings/download_view.dart';
import 'package:tipitaka_pali/ui/screens/settings/settings.dart';
import 'package:tipitaka_pali/ui/screens/splash_screen.dart';
import 'package:tipitaka_pali/utils/platform_info.dart';

import 'services/prefs.dart';
import 'ui/screens/reader/mobile_reader_container.dart';

const splashRoute = '/';
const homeRoute = '/home';
const readerRoute = '/reader';
const searchRoute = '/search';
const searchResultRoute = '/search_result_view';
const settingRoute = '/setting';
const dictionaryRoute = '/dictionary';

final GlobalKey<NavigatorState> searchNavigationKey = GlobalKey();
final GlobalKey<NavigatorState> settingNavigationKey = GlobalKey();
final GlobalKey<NavigatorState> dictionaryNavigationKey = GlobalKey();

// Not supporting of web version of this app, using named route is not essentail.
class RouteGenerator {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    final arguments = settings.arguments;

    Widget screen = Home();
    switch (settings.name) {
      case splashRoute:
        screen = SplashScreen();
        break;
      case homeRoute:
        screen = const Home();
        break;
      case dictionaryRoute:
        screen = const DictionaryPage();
        break;
      case searchRoute:
        screen = const SearchPage();
        break;
      case searchResultRoute:
        if (arguments is Map) {
          screen = SearchResultPage(
              searchWord: arguments['searchWord'],
              queryMode: arguments['queryMode'],
              wordDistance: arguments['wordDistance']);
        }
        break;
      case readerRoute:
        if (arguments is Map) {
          screen = Reader(
            book: arguments['book'],
            initialPage: arguments['currentPage'],
            textToHighlight: arguments['textToHighlight'],
            bookViewMode: PlatformInfo.isDesktop
                ? BookViewMode.horizontal
                : BookViewMode.values[Prefs.bookViewModeIndex],
            bookUuid: arguments['uuid'],
          );
        }
        break;
      case settingRoute:
        screen = const SettingPage();
        break;
      case '/extension-dialog':
        screen = const ExtensionPromptDialog(
          message: '',
        );
        break;
      case '/book-import-view':
        screen = const BookImportView();
        break;
      case '/download-view':
        screen = const DownloadView();
        break;
      case '/text-converter-view':
        screen = const TextConverterView();
        break;
    }
    return MaterialPageRoute(builder: (BuildContext context) => screen);
  }
}

class NestedNavigationHelper {
  NestedNavigationHelper._();
  static void goto(
      {required BuildContext context,
      required MaterialPageRoute route,
      required GlobalKey<NavigatorState> navkey}) {
    if (Mobile.isPhone(context)) {
      Navigator.push(context, route);
      return;
    }

    navkey.currentState!.push(route);
  }

  static Widget buildPage(
      {required BuildContext context,
      required Widget screen,
      required GlobalKey<NavigatorState> key}) {
    if (Mobile.isPhone(context)) return screen;

    return Navigator(
      key: key,
      onGenerateRoute: (setting) {
        return MaterialPageRoute(builder: (_) => screen);
      },
    );
  }
}
