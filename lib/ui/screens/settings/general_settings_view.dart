import 'package:flutter/material.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:tipitaka_pali/services/prefs.dart';

enum Startup { quoteOfDay, restoreLastRead }

class GeneralSettingsView extends StatefulWidget {
  const GeneralSettingsView({super.key});

  @override
  State<GeneralSettingsView> createState() => _GeneralSettingsViewState();
}

class _GeneralSettingsViewState extends State<GeneralSettingsView> {
  bool _clipboard = Prefs.saveClickToClipboard;
  bool _disableVelthuis = Prefs.disableVelthuis;
  bool _persitentSearchFilter = Prefs.persitentSearchFilter;

  @override
  void initState() {
    super.initState();
    _clipboard = Prefs.saveClickToClipboard;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.settings),
        title: Text(AppLocalizations.of(context)!.generalSettings,
            style: Theme.of(context).textTheme.titleLarge),
        children: [
          _getAnimationsSwitch(),
          const SizedBox(
            height: 10,
          ),
          const SizedBox(
            height: 10,
          ),
          const Divider(),
          _getDictionaryToClipboardSwitch(),
          const Divider(),
          _getVelthuisOnSwitch(),
          const Divider(),
          _getPersitentSearchFilterSwitch(),
          const Divider(),
          _getMultiHighlightSwitch(),
          const Divider(),
          _getAlwaysShowSplitterSwitch(),
          const Divider(),
          _getShowWhatsNewSwitch(),
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
              label: Prefs.animationSpeed.round().toString(),
              onChanged: (double value) {
                setState(() {
                  Prefs.animationSpeed = value;
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

  Widget _getMultiHighlightSwitch() {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: Text(AppLocalizations.of(context)!
            .multiHighlight), // You might want to localize this string as well
        trailing: Switch(
          onChanged: (value) {
            setState(() {
              Prefs.multiHighlight = value;
            });
          },
          value: Prefs.multiHighlight,
        ),
      ),
    );
  }

/*  Widget _getQuotesOrRestore() {
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
  */

  Widget _getAlwaysShowSplitterSwitch() {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: Text(AppLocalizations.of(context)!.alwaysShowSplitter),
        trailing: Switch(
          onChanged: (value) {
            setState(() {
              Prefs.alwaysShowDpdSplitter = value;
            });
          },
          value: Prefs.alwaysShowDpdSplitter,
        ),
      ),
    );
  }

  Widget _getShowWhatsNewSwitch() {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: Text(AppLocalizations.of(context)!.showWhatsNew),
        trailing: Switch(
          onChanged: (value) {
            setState(() {
              Prefs.showWhatsNew = value;
            });
          },
          value: Prefs.showWhatsNew,
        ),
      ),
    );
  }

  Widget _getVelthuisOnSwitch() {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: Text(AppLocalizations.of(context)!.disableVelthuis),
        trailing: Switch(
          onChanged: (value) {
            setState(() {
              _disableVelthuis = Prefs.disableVelthuis = value;
            });
          },
          value: _disableVelthuis,
        ),
      ),
    );
  }

  Widget _getPersitentSearchFilterSwitch() {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: Text(AppLocalizations.of(context)!.persistentSearchFilter),
        trailing: Switch(
          onChanged: (value) {
            setState(() {
              _persitentSearchFilter = Prefs.persitentSearchFilter = value;
            });
          },
          value: _persitentSearchFilter,
        ),
      ),
    );
  }
}
