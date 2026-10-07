import 'package:flutter/material.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:tipitaka_pali/ui/screens/settings/settings.dart';
import 'package:tipitaka_pali/ui/widgets/select_font_widget.dart';
import 'package:tipitaka_pali/ui/widgets/select_theme_widget.dart';
import 'package:tipitaka_pali/ui/widgets/use_m3_widget.dart';

class ThemeSettingView extends StatelessWidget {
  const ThemeSettingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.color_lens),
        title: Text(AppLocalizations.of(context)!.theme,
            style: Theme.of(context).textTheme.titleLarge),
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 32.0),
            child: DarkModeSettingView(),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 32.0),
            child: ListTile(
              title: Text(
                AppLocalizations.of(context)!.color,
              ),
              trailing: const SelectThemeWidget(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 32.0),
            child: ListTile(
              title: Text(AppLocalizations.of(context)!.material3),
              trailing: const M3SwitchWidget(),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 32.0),
            child: ScriptFontTile(),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 32.0),
            child: TranslationFontTiles(),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 32.0),
            child: AppFontTile(),
          ),
        ],
      ),
    );
  }
}
