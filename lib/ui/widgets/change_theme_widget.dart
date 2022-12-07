import 'package:tipitaka_pali/services/provider/theme_change_notifier.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/services/prefs.dart';

class ChangeThemeWidget extends StatelessWidget {
  const ChangeThemeWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    //final themeProvider = Provider.of<ThemeChangeNotifier>(context);

// This code is not used.. old code
// now use 3 state button
    return Switch(
      value: Prefs.darkThemeOn,
      activeThumbImage: const AssetImage("assets/sun.png"),
      inactiveThumbImage: const AssetImage("assets/moon.png"),
      onChanged: (value) {
        final provider =
            Provider.of<ThemeChangeNotifier>(context, listen: false);
        Prefs.darkThemeOn = value;
        provider.toggleTheme(Prefs.selectedPageColor); // not used.. old cod
      },
    );
  }
}
