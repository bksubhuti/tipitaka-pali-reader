import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/services/provider/bookmark_provider.dart';
import 'package:tipitaka_pali/services/provider/theme_change_notifier.dart';
import 'package:tipitaka_pali/ui/screens/settings/sync_settings.dart';
import 'package:tipitaka_pali/ui/screens/settings/theme_settings_view.dart';
import 'package:tipitaka_pali/ui/screens/settings/tools_settings.dart';
import 'package:tipitaka_pali/ui/widgets/select_dictionary_widget.dart';
import 'package:tipitaka_pali/ui/widgets/select_language_widget.dart';

import 'general_settings_view.dart';
import 'help_about.dart';
import 'script_setting_view.dart';

class SettingPage extends StatelessWidget {
  const SettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sc = ScrollController(); // for auto scroll

    return Scaffold(
        extendBody: true,
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.settings),
          actions: const [],
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: ListView(
            controller: sc, // Attach the ScrollController to ListVie
            children: <Widget>[
              const SizedBox(height: 16),
              const DictionarySettingView(),
              const ThemeSettingView(),
              const LanguageSettingView(),
              const ScriptSettingView(),
              const GeneralSettingsView(),
              const HelpAboutView(),
              ChangeNotifierProvider<BookmarkNotifier>(
                create: (context) => BookmarkNotifier(),
                child: const SyncSettingsView(),
              ),
              ToolsSettingsView(scrollController: sc),
            ],
          ),
        ));
  }
}

class DarkModeSettingView extends StatelessWidget {
  const DarkModeSettingView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      trailing: Consumer<ThemeChangeNotifier>(
          builder: ((context, themeChangeNotifier, child) => ToggleButtons(
                onPressed: (int index) {
                  Provider.of<ThemeChangeNotifier>(context, listen: false)
                      .toggleTheme(index);
                },
                isSelected: context.read<ThemeChangeNotifier>().isSelected,
                children: const <Widget>[
                  Icon(Icons.wb_sunny),
                  Icon(Icons.color_lens),
                  Icon(Icons.bedtime),
                ],
              ))),
      title: Text(
        AppLocalizations.of(context)!.darkMode,
      ),
    );
  }
}

class LanguageSettingView extends StatelessWidget {
  const LanguageSettingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.language_outlined),
        title: Text(
          AppLocalizations.of(context)!.language,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        trailing: SelectLanguageWidget(),
      ),
    );
  }
}

class DictionarySettingView extends StatelessWidget {
  const DictionarySettingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.sort_by_alpha_outlined),
        title: Text(AppLocalizations.of(context)!.dictionaries,
            style: Theme.of(context).textTheme.titleLarge),
        children: const [SelectDictionaryWidget()],
      ),
    );
  }
}
