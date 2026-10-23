import 'package:flutter/material.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../services/provider/theme_change_notifier.dart';
import 'select_script_language.dart';

class ScriptSettingView extends StatelessWidget {
  const ScriptSettingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeChangeNotifier>(
      builder: (context, notifier, child) {
        return Card(
          child: ExpansionTile(
            leading: const Icon(Icons.font_download_outlined),
            title: Text(AppLocalizations.of(context)!.paliScript,
                style: Theme.of(context).textTheme.titleLarge),
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 32.0),
                child: ListTile(
                  title: Text(AppLocalizations.of(context)!.scriptLanguage),
                  trailing: const SelectScriptLanguageWidget(),
                ),
              ),
              _switch(
                AppLocalizations.of(context)!.showAlternatePali,
                notifier.showAlternatePali,
                notifier.onChangeShowAlternatePali,
              ),
              _switch(
                AppLocalizations.of(context)!.showPTSPageNumber,
                notifier.showPtsNumber,
                notifier.onChangeShowPtsNumber,
              ),
              _switch(
                AppLocalizations.of(context)!.showThaiPageNumber,
                notifier.showThaiNumber,
                notifier.onChangeShowThaiNumber,
              ),
              _switch(
                AppLocalizations.of(context)!.showVRIPageNumber,
                notifier.showVriNumber,
                notifier.onChangeShowVriNumber,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _switch(String title, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: Text(title),
        trailing: Switch(onChanged: onChanged, value: value),
      ),
    );
  }
}
