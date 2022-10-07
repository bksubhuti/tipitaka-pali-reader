import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/ui/screens/settings/download_view.dart';

import '../../../business_logic/view_models/script_settings_view_model.dart';
import 'select_script_language.dart';
import 'download_view.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import '../../widgets/colored_text.dart';

enum Startup { quoteOfDay, restoreLastRead }

class GeneralSettingsView extends StatefulWidget {
  const GeneralSettingsView({Key? key}) : super(key: key);

  @override
  State<GeneralSettingsView> createState() => _GeneralSettingsViewState();
}

class _GeneralSettingsViewState extends State<GeneralSettingsView> {
  bool _clipboard = Prefs.saveClickToClipboard;
  @override
  void initState() {
    _clipboard = Prefs.saveClickToClipboard; // TODO: implement initState
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      child: ExpansionTile(
        leading: const Icon(Icons.settings),
        title: Text("General", style: Theme.of(context).textTheme.headline6),
        children: [
          DictionaryToClipboardSwitch(),
          SizedBox(
            height: 20,
          ),
          //DownloadTile(context),
          //QuotesOrRestore(),
          AboutTile(context),
        ],
      ),
    );
  }

  Widget AnimationsSwitch() {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: const Text("Animations"),
        trailing: Switch(
          onChanged: (value) => {
            //prefs
          },
          value: true,
        ),
      ),
    );
  }

  Widget DictionaryToClipboardSwitch() {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: const Text("Dictionary to Clipboard"),
        trailing: Switch(
          onChanged: (value) {
            setState(() {
              _clipboard = Prefs.saveClickToClipboard = value;
            });
          },
          value: _clipboard,
        ),
      ),
    );
  }

  Widget DownloadTile(context) {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ElevatedButton(
          child: const Text('Download Pali/English Books'),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const DownloadView()),
            );
          }),
    );
  }

  Widget QuotesOrRestore() {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: const Text("Quote -> Restore:"),
        trailing: Switch(
          onChanged: (value) => {
            //prefs
          },
          value: true,
        ),
      ),
    );
  }

  Widget AboutTile(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: Text(AppLocalizations.of(context)!.about),
        onTap: () => _showAboutDialog(context),
      ),
    );
  }

  _showAboutDialog(BuildContext context) {
    showAboutDialog(
        context: context,
        applicationName: AppLocalizations.of(context)!.tipitaka_pali_reader,
        applicationVersion: 'Version 1.5',
        children: [ColoredText(AppLocalizations.of(context)!.about_info)]);
  }
}
