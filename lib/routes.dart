import 'package:flutter/material.dart';
import 'package:tipitaka_pali/ui/screens/dictionary/dictionary_page.dart';
import 'package:tipitaka_pali/ui/screens/home/home_container.dart';
import 'package:tipitaka_pali/ui/screens/home/quick_jump_page.dart';
import 'package:tipitaka_pali/ui/screens/home/search_page/search_page.dart';
import 'package:tipitaka_pali/ui/screens/reader/reader.dart';
import 'package:tipitaka_pali/ui/screens/search_result/search_result_page.dart';
import 'package:tipitaka_pali/ui/screens/settings/settings.dart';
import 'package:tipitaka_pali/ui/screens/splash_screen.dart';

const splashRoute = '/';
const homeRoute = '/home';
const readerRoute = '/reader';
const searchRoute = '/search';
const searchResultRoute = '/search_result_view';
const settingRoute = '/setting';
const dictionaryRoute = '/dictionary';
const quickJumpRoute = '/quickjump';

class RouteGenerator {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    final arguments = settings.arguments;

    late Widget screen;
    switch (settings.name) {
      case splashRoute:
        screen = const SplashScreen();
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
          );
        }
        break;
      case settingRoute:
        screen = const SettingPage();
        break;
      case quickJumpRoute:
        screen = const QuickJumpPage();
        break;
    }
    return MaterialPageRoute(builder: (BuildContext context) => screen);
  }
}
