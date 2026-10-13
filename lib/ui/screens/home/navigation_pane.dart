import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/providers/navigation_provider.dart';

import '../../../routes.dart';
import '../ai_search/ai_search_page.dart';
import '../dictionary/dictionary_page.dart';
import '../settings/settings.dart';
import 'book_list_page.dart';
import 'bookmark_page.dart';
import 'recent_page.dart';
import 'search_page/search_page.dart';

class DetailNavigationPane extends StatefulWidget {
  const DetailNavigationPane({super.key, required this.navigationCount});
  final int navigationCount;

  @override
  State<DetailNavigationPane> createState() => _DetailNavigationPaneState();
}

class _DetailNavigationPaneState extends State<DetailNavigationPane> {
  late final NavigationProvider navigationProvider;
  late final PageController pageController;

  @override
  void initState() {
    super.initState();
    pageController = PageController();
    navigationProvider = context.read<NavigationProvider>();
    navigationProvider.addListener(_pageChangeListener);
  }

  @override
  void dispose() {
    navigationProvider.removeListener(_pageChangeListener);
    pageController.dispose();
    super.dispose();
  }

  void _pageChangeListener() {
    int index = context.read<NavigationProvider>().currentNavigation;
    int settingIndex =
        context.read<NavigationProvider>().indexOfSettingNavigation;
    if (index == settingIndex) {
      // debugPrint('clicked setting icon');
      cleanSettingNavigationStack();
    }
    pageController.jumpToPage(index);
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
        controller: pageController,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: widget.navigationCount, // todo
        itemBuilder: (context, index) {
          return _getPage(context, index);
        });
  }

  Widget _getPage(BuildContext context, int index) {
    switch (index) {
      case 0:
        return BookListPage();
      case 1:
        return const RecentPage();
      case 2:
        return const BookmarkPage();
      case 3:
        return NestedNavigationHelper.buildPage(
          context: context,
          screen: const SearchPage(),
          key: searchNavigationKey,
        );
      // if (PlatformInfo.isDesktop || Mobile.isTablet(context)) {
      //   return Navigator(
      //     key: searchNavigationKey,
      //     onGenerateRoute: (setting) {
      //       return MaterialPageRoute(builder: (_) => const SearchPage());
      //     },
      //   );
      // } else {
      //   return const SearchPage();
      // }
      case 4:
        return NestedNavigationHelper.buildPage(
          context: context,
          screen: const DictionaryPage(),
          key: dictionaryNavigationKey,
        );
      // only in desktop
      case 5:
        // clean navigation stacks
        return NestedNavigationHelper.buildPage(
          context: context,
          screen: const SettingPage(),
          key: settingNavigationKey,
        );
      // only in desktop: AI search as its own panel, as well as from the
      // search panel's mode buttons
      case 6:
        return NestedNavigationHelper.buildPage(
          context: context,
          screen: const AiSearchPage(query: ''),
          key: aiSearchNavigationKey,
        );
      default:
        throw Error();
    }
  }

  void cleanSettingNavigationStack() {
    while (settingNavigationKey.currentState?.canPop() == true) {
      settingNavigationKey.currentState?.pop();
      debugPrint('clean setting navigation stack');
    }
  }
}
