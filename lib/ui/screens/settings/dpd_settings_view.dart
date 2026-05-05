import 'package:flutter/material.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:tipitaka_pali/services/prefs.dart';

class DPDSettingsView extends StatefulWidget {
  const DPDSettingsView({super.key});

  @override
  State<DPDSettingsView> createState() => _DPDSettingsViewState();
}

class _DPDSettingsViewState extends State<DPDSettingsView> {
  bool _clipboard = Prefs.saveClickToClipboard;
  bool _disableVelthuis = Prefs.disableVelthuis;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.dock_outlined),
        title: Text(AppLocalizations.of(context)!.dpdSettings,
            style: Theme.of(context).textTheme.titleLarge),
        children: [
          _getDpdGrammarSwitch(),
          const Divider(),
          _getHideIPASwitch(),
          _getHideSanskritSwitch(),
        ],
      ),
    );
  }

  Widget _getDpdGrammarSwitch() {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: const Text("DPD Grammar (Word Forms)"),
        trailing: Switch(
          onChanged: (value) {
            setState(() {
              Prefs.isDpdGrammarOn = value;
            });
          },
          value: Prefs.isDpdGrammarOn,
        ),
      ),
    );
  }

  Widget _getHideIPASwitch() {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: Text(AppLocalizations.of(context)!.hideIPA),
        trailing: Switch(
          onChanged: (value) {
            setState(() {
              Prefs.hideIPA = value;
            });
          },
          value: Prefs.hideIPA,
        ),
      ),
    );
  }

  Widget _getHideSanskritSwitch() {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: Text(AppLocalizations.of(context)!
            .hideSanskrit), // You might want to localize this string as well
        trailing: Switch(
          onChanged: (value) {
            setState(() {
              Prefs.hideSanskrit = value;
            });
          },
          value: Prefs.hideSanskrit,
        ),
      ),
    );
  }
}
