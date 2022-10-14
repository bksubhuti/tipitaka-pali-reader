import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
//import 'package:tipitaka_pali/ui/screens/settings/download_view.dart';

import 'package:tipitaka_pali/services/prefs.dart';
import '../../widgets/colored_text.dart';
import 'package:url_launcher/url_launcher.dart';

enum Startup { quoteOfDay, restoreLastRead }

class GeneralSettingsView extends StatefulWidget {
  const GeneralSettingsView({Key? key}) : super(key: key);

  @override
  State<GeneralSettingsView> createState() => _GeneralSettingsViewState();
}

class _GeneralSettingsViewState extends State<GeneralSettingsView> {
  bool _clipboard = Prefs.saveClickToClipboard;
  double _currentSliderValue = 1;
  @override
  void initState() {
    _clipboard = Prefs.saveClickToClipboard;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      child: ExpansionTile(
        leading: const Icon(Icons.settings),
        title: Text(AppLocalizations.of(context)!.generalSettings,
            style: Theme.of(context).textTheme.headline6),
        children: [
          _getDictionaryToClipboardSwitch(),
          const SizedBox(
            height: 20,
          ),
          _getAnimationsSwitch(),
          _getHelpTile(context),
          _getAboutTile(context),
          //DownloadTile(context),
          //QuotesOrRestore(),
          _getReportIssueTile(context),
        ],
      ),
    );
  }

  Widget _getAnimationsSwitch() {
    return Padding(
        padding: const EdgeInsets.only(left: 32.0),
        child: Column(
          children: [
            Slider(
              value: Prefs.animationSpeed,
              max: 800,
              divisions: 20,
              label: _currentSliderValue.round().toString(),
              onChanged: (double value) {
                setState(() {
                  Prefs.animationSpeed = _currentSliderValue = value;
                });
              },
            ),
            Text(AppLocalizations.of(context)!.animationSpeed),
          ],
        ));
  }

  Widget _getDictionaryToClipboardSwitch() {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: Text(AppLocalizations.of(context)!.dictionaryToClipboard),
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

  Widget _getDownloadTile(context) {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ElevatedButton(
          child: const Text('Download Pali/English Books'),
          onPressed: () {
//            Navigator.push(
            //            context,
            //          MaterialPageRoute(builder: (context) => const DownloadView()),
            //      );
          }),
    );
  }

  Widget _getQuotesOrRestore() {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: const Text("Quote -> Restore:"),
        focusColor: Theme.of(context).focusColor,
        hoverColor: Theme.of(context).hoverColor,
        trailing: Switch(
          onChanged: (value) => {
            //prefs
          },
          value: true,
        ),
      ),
    );
  }

  Widget _getAboutTile(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: ColoredText(AppLocalizations.of(context)!.about),
        focusColor: Theme.of(context).focusColor,
        hoverColor: Theme.of(context).hoverColor,
        onTap: () => _showAboutDialog(context),
      ),
    );
  }

  _showAboutDialog(BuildContext context) {
    showAboutDialog(
        context: context,
        applicationName: AppLocalizations.of(context)!.tipitaka_pali_reader,
        applicationVersion: 'Version 1.6',
        children: [ColoredText(AppLocalizations.of(context)!.about_info)]);
  }

  Widget _getHelpTile(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: ColoredText(AppLocalizations.of(context)!.help),
        focusColor: Theme.of(context).focusColor,
        hoverColor: Theme.of(context).hoverColor,
        onTap: () => launchUrl(
            Uri.parse("https://americanmonk.org/tipitaka-pali-reader/"),
            mode: LaunchMode.externalApplication),
      ),
    );
  }

  Widget _getReportIssueTile(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: ColoredText(AppLocalizations.of(context)!.reportIssue),
        focusColor: Theme.of(context).focusColor,
        hoverColor: Theme.of(context).hoverColor,
        onTap: () => launchUrl(
            Uri.parse(
                "https://github.com/bksubhuti/tipitaka-pali-reader/issues"),
            mode: LaunchMode.externalApplication),
      ),
    );
  }
}
