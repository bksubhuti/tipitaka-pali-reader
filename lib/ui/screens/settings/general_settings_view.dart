import 'package:flutter/material.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/ui/screens/home/openning_books_provider.dart';
import 'package:tipitaka_pali/ui/screens/reader/widgets/quote_of_day.dart';

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
          _getQuoteListDropdown(),
          const Divider(),
          _getRestoreTabsSwitch(),
          const Divider(),
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
        ],
      ),
    );
  }

  /// Which list the home screen's quote comes from.
  Widget _getQuoteListDropdown() {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: Text(l.homeScreenQuote),
        // Under the title, not beside it: side by side is too wide.
        subtitle: Align(
          alignment: AlignmentDirectional.centerStart,
          child: DropdownButton<QuoteList>(
            value: quoteList.value,
            items: [
              DropdownMenuItem(
                  value: QuoteList.versesToKnow, child: Text(l.versesToKnow)),
              DropdownMenuItem(
                  value: QuoteList.dailyBuddhaVacana,
                  child: Text(l.dailyBuddhaVacana)),
            ],
            onChanged: (list) {
              if (list == null) return;
              setState(() {
                Prefs.quoteList = list.id;
                quoteList.value = list;
              });
            },
          ),
        ),
      ),
    );
  }

  /// Whether TPR offers, at startup, to reopen the books that were open.
  Widget _getRestoreTabsSwitch() {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: Text(l.restoreTabs),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          SettingInfoButton(l.restoreTabsSubtitle),
          Switch(
            value: Prefs.restoreTabs,
            onChanged: (value) {
              setState(() => Prefs.restoreTabs = value);
              if (value) {
                // Keep what is open now, not only what opens from here on.
                context.read<OpenningBooksProvider>().saveTabs();
              } else {
                Prefs.savedTabs = null;
              }
            },
          ),
        ]),
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

/// An ⓘ beside a setting, showing what it does in a box, so the list of
/// settings can be names alone.
class SettingInfoButton extends StatelessWidget {
  final String text;

  const SettingInfoButton(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.info_outline, size: 20),
      color: Theme.of(context).hintColor,
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.close),
            ),
          ],
        ),
      ),
    );
  }
}
