import 'package:flutter/material.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/data/constants.dart';
import 'package:tipitaka_pali/providers/navigation_provider.dart';
import 'package:tipitaka_pali/ui/screens/reader/mobile_reader_container.dart';
import 'package:tipitaka_pali/utils/platform_info.dart';

class DeskTopNavigationBar extends StatelessWidget {
  const DeskTopNavigationBar({
    super.key,
    // required this.selectedIndex,
    // this.onDestinationSelected,
  });

  // final int selectedIndex;
  // final ValueChanged<int>? onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.zero;

    final currentNaviagtionItem = context
        .select<NavigationProvider, int>((value) => value.currentNavigation);

    final navigation = context.read<NavigationProvider>();
    // The rail shows the panels in this order; each place on it stands for a
    // panel number, which is not always its position: AI search sits below
    // Search but has the last number.
    final order = [0, 1, 2, 3, navigation.indexOfAiSearchNavigation, 4, 5];
    final selected = order.indexOf(currentNaviagtionItem);

    return NavigationRail(
      minWidth: navigationBarWidth,
      // In the phone's ☰ panel, a tap on the logo closes the panel. Not
      // there on a phone held sideways, which is short of room for the rail.
      leading: Mobile.isPhone(context) &&
              MediaQuery.orientationOf(context) == Orientation.landscape
          ? null
          : Ink.image(
              height: navigationBarWidth,
              width: navigationBarWidth,
              image: const AssetImage('assets/icon/icon.png'),
              fit: BoxFit.scaleDown,
              child: Mobile.isPhone(context)
                  ? InkWell(
                      onTap: MobileReaderContainer.closePanel)
                  : null,
            ),
      useIndicator: true,
      labelType: NavigationRailLabelType.none,
      destinations: [
        NavigationRailDestination(
          icon: Tooltip(
              message: AppLocalizations.of(context)!.home,
              child: const Icon(Icons.home_outlined)),
          selectedIcon: const Icon(Icons.home),
          label: Text(AppLocalizations.of(context)!.home),
          padding: padding,
        ),
        NavigationRailDestination(
          icon: Tooltip(
              message: AppLocalizations.of(context)!.recent,
              child: const Icon(Icons.history_outlined)),
          selectedIcon: const Icon(Icons.history),
          label: Text(AppLocalizations.of(context)!.recent),
          padding: padding,
        ),
        NavigationRailDestination(
          icon: Tooltip(
              message: AppLocalizations.of(context)!.bookmark,
              child: const Icon(Icons.bookmark_outline)),
          selectedIcon: const Icon(Icons.bookmark),
          label: Text(AppLocalizations.of(context)!.bookmark),
          padding: padding,
        ),
        NavigationRailDestination(
          icon: Tooltip(
              message: AppLocalizations.of(context)!.search,
              child: const Icon(Icons.search)),
          selectedIcon: const Icon(Icons.search_outlined),
          label: Text(AppLocalizations.of(context)!.search),
          padding: padding,
        ),
        NavigationRailDestination(
          icon: Tooltip(
              message: AppLocalizations.of(context)!.aiSearch,
              child: const Icon(Icons.auto_awesome_outlined)),
          selectedIcon: const Icon(Icons.auto_awesome),
          label: Text(AppLocalizations.of(context)!.aiSearch),
          padding: padding,
        ),
        NavigationRailDestination(
          icon: Tooltip(
              message: AppLocalizations.of(context)!.dictionary,
              child: Image.asset("assets/icon/tpr_dictionary.png",
                  width: 24,
                  height: 24,
                  color: Theme.of(context).iconTheme.color)),
          selectedIcon: Tooltip(
              message: AppLocalizations.of(context)!.dictionary,
              child: Image.asset(
                "assets/icon/tpr_dictionary.png",
                width: 24,
                height: 24,
                color: Theme.of(context).primaryColor,
              )),
          label: Text(AppLocalizations.of(context)!.dictionary),
          padding: padding,
        ),
        NavigationRailDestination(
          icon: Tooltip(
              message: AppLocalizations.of(context)!.settings,
              child: const Icon(Icons.settings_outlined)),
          selectedIcon: const Icon(Icons.settings),
          label: Text(AppLocalizations.of(context)!.settings),
          padding: padding,
        ),
      ],
      // labelType: NavigationRailLabelType.all,
      selectedIndex: selected < 0 ? null : selected,
      onDestinationSelected: (index) =>
          navigation.onClickedNavigationItem(order[index]),
    );
  }
}
