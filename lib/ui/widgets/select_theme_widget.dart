import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/data/flex_theme_data.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/provider/theme_change_notifier.dart';
import 'package:tipitaka_pali/ui/widgets/colored_text.dart';

class SelectThemeWidget extends StatelessWidget {
  const SelectThemeWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isLight = theme.brightness == Brightness.light;
    final themeChangeNotifier = Provider.of<ThemeChangeNotifier>(context);

    // Extracting the current theme's primary and secondary colors
    final currentPrimaryColor = isLight
        ? myFlexSchemes[Prefs.themeIndex].light.primary
        : myFlexSchemes[Prefs.themeIndex].dark.primary;
    final currentSecondaryColor = isLight
        ? myFlexSchemes[Prefs.themeIndex].light.secondary
        : myFlexSchemes[Prefs.themeIndex].dark.secondary;

    // PopupMenuButton for theme selection. The name and the colour samples
    // open it too, not just the arrow.
    return PopupMenuButton<int>(
      padding: EdgeInsets.zero,
      // Over the whole window, so a click anywhere outside the menu, on the
      // reader too, closes it; narrow, so it still fits the Settings panel.
      useRootNavigator: true,
      constraints: const BoxConstraints(maxWidth: 240),
      // Just under its row, not over it: over it, a long list is pushed up
      // to the top of the window, away from the row.
      position: PopupMenuPosition.under,
      onSelected: (val) {
        Prefs.themeIndex = val;
        Prefs.themeName = myFlexSchemes[val].name;
        themeChangeNotifier.themeIndex = val;
      },
      itemBuilder: (BuildContext context) => <PopupMenuItem<int>>[
        for (int i = 0; i < myFlexSchemes.length; i++)
          PopupMenuItem<int>(
            value: i,
            // A plain row, narrower than a ListTile, so the menu stays
            // inside the Settings panel.
            child: Row(
              children: [
                Icon(Icons.lens,
                    color: isLight
                        ? myFlexSchemes[i].light.primary
                        : myFlexSchemes[i].dark.primary,
                    size: 28),
                const SizedBox(width: 4),
                Icon(Icons.circle,
                    color: isLight
                        ? myFlexSchemes[i].light.secondary
                        : myFlexSchemes[i].dark.secondary,
                    size: 18),
                const SizedBox(width: 12),
                ColoredText(myFlexSchemes[i].name),
              ],
            ),
          )
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Display current theme name and color icons
          ColoredText(
            myFlexSchemes[Prefs.themeIndex].name,
          ),
          const SizedBox(width: 8),
          Icon(Icons.lens, color: currentPrimaryColor, size: 26),
          Icon(Icons.lens, color: currentSecondaryColor, size: 20),
          const SizedBox(width: 8),
          const Icon(
            Icons.arrow_drop_down,
          ),
        ],
      ),
    );
  }
}
