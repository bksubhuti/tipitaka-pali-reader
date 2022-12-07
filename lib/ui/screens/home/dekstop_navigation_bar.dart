import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:tipitaka_pali/data/constants.dart';
import 'package:tipitaka_pali/providers/navigation_provider.dart';
import 'package:provider/provider.dart';

class DeskTopNavigationBar extends StatelessWidget {
  const DeskTopNavigationBar({
    Key? key,
    // required this.selectedIndex,
    // this.onDestinationSelected,
  }) : super(key: key);

  // final int selectedIndex;
  // final ValueChanged<int>? onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.zero;

    final currentNaviagtionItem = context
        .select<NavigationProvider, int>((value) => value.currentNavigation);

    return NavigationRail(
      minWidth: navigationBarWidth,
      indicatorColor: Theme.of(context).focusColor,
      leading: Ink.image(
        height: navigationBarWidth,
        width: navigationBarWidth,
        image: const AssetImage('assets/icon/icon.png'),
        fit: BoxFit.scaleDown,
      ),
      useIndicator: true,
      labelType: NavigationRailLabelType.none,
      destinations: [
        NavigationRailDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home),
          label: Text(AppLocalizations.of(context)!.home),
          padding: padding,
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.history_outlined),
          selectedIcon: const Icon(Icons.history),
          label: Text(AppLocalizations.of(context)!.recent),
          padding: padding,
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.bookmark_outline),
          selectedIcon: const Icon(Icons.bookmark),
          label: Text(AppLocalizations.of(context)!.bookmark),
          padding: padding,
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.search),
          selectedIcon: const Icon(Icons.search_outlined),
          label: Text(AppLocalizations.of(context)!.search),
          padding: padding,
        ),
        NavigationRailDestination(
          icon: Image.asset("assets/icon/tpr_dictionary.png",
              width: 24, height: 24, color: Theme.of(context).iconTheme.color),
          selectedIcon: Image.asset(
            "assets/icon/tpr_dictionary.png",
            width: 24,
            height: 24,
            color: Theme.of(context).primaryColor,
          ),
          label: Text(AppLocalizations.of(context)!.dictionary),
          padding: padding,
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.settings_outlined),
          selectedIcon: const Icon(Icons.settings),
          label: Text(AppLocalizations.of(context)!.settings),
          padding: padding,
        ),
      ],
      // labelType: NavigationRailLabelType.all,
      selectedIndex: currentNaviagtionItem,
      onDestinationSelected: (index) =>
          context.read<NavigationProvider>().onClickedNavigationItem(index),
    );
  }
}
