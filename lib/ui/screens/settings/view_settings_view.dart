import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart'; // Ensure this is in pubspec.yaml
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/provider/theme_change_notifier.dart';

class ViewSettingsView extends StatefulWidget {
  const ViewSettingsView({super.key});

  @override
  State<ViewSettingsView> createState() => _ViewSettingsViewState();
}

class _ViewSettingsViewState extends State<ViewSettingsView> {
  late bool _hideScrollbar;
  late final StreamingSharedPreferences rxPrefs;

  @override
  void initState() {
    super.initState();
    rxPrefs = Provider.of<StreamingSharedPreferences>(context, listen: false);
    _hideScrollbar = rxPrefs
        .getBool(hideScrollbarPref, defaultValue: defaultHideScrollbar)
        .getValue();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.visibility),
        title: Text(
          AppLocalizations.of(context)!.viewSettings,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        children: [
          _getUiFontSizeSlider(),
          const Divider(),
          _getDictionaryFontSizeSlider(),
          const Divider(),
          _getPaliTextColorSetting(),
          const Divider(),
          _getTranslationColorSetting(),
          const Divider(),
          _getHideScrollbarSwitch(),
          const Divider(),
          _getMultiTabsModeSwitch(),
          const Divider(),
          _getNewTabAtEndSwitch(),
          const Divider(),
          _getExpandedBookListSwitch(),
          const Divider(),
          _getShowTranslationsSwitch(),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _getUiFontSizeSlider() {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: Column(
        children: [
          Slider(
            value: Prefs.uiFontSize,
            min: 8,
            max: 24,
            divisions: 16,
            label: Prefs.uiFontSize.round().toString(),
            onChanged: (double value) {
              context.read<ThemeChangeNotifier>().onChangeFontSize(value);
            },
          ),
          Text(AppLocalizations.of(context)!.uiFontSize),
        ],
      ),
    );
  }

  Widget _getDictionaryFontSizeSlider() {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: Column(
        children: [
          Slider(
            value: Prefs.dictionaryFontSize.toDouble(),
            min: 8,
            max: 20,
            divisions: 12,
            label: Prefs.dictionaryFontSize.toString(),
            onChanged: (double value) {
              setState(() {
                Prefs.dictionaryFontSize = value.toInt();
              });
            },
          ),
          Text(AppLocalizations.of(context)!.dictionaryFontSize),
        ],
      ),
    );
  }

  Widget _getPaliTextColorSetting() {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: Text(AppLocalizations.of(context)!.paliTextColor),
        trailing: _colorIndicator(Color(Prefs.paliTextColor)),
        onTap: () => _openColorPicker(
          AppLocalizations.of(context)!.paliTextColor,
          Prefs.paliTextColor,
          (colorValue) {
            setState(() {
              Prefs.paliTextColor = colorValue;
            });
          },
        ),
      ),
    );
  }

  Widget _getTranslationColorSetting() {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: Text(AppLocalizations.of(context)!.translationColor),
        trailing: _colorIndicator(Color(Prefs.translationColor)),
        onTap: () => _openColorPicker(
          AppLocalizations.of(context)!.translationColor,
          Prefs.translationColor,
          (colorValue) {
            setState(() {
              Prefs.translationColor = colorValue;
            });
          },
        ),
      ),
    );
  }

  // Helper for the UI circle showing the current color
  Widget _colorIndicator(Color color) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.withOpacity(0.5), width: 2),
      ),
    );
  }

  Widget _getHideScrollbarSwitch() {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: const Text("Hide Scrollbars"),
        trailing: Switch(
          onChanged: (value) async {
            setState(() => _hideScrollbar = value);
            await rxPrefs.setBool(hideScrollbarPref, _hideScrollbar);
          },
          value: _hideScrollbar,
        ),
      ),
    );
  }

  Widget _getMultiTabsModeSwitch() {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: Column(
        children: [
          ListTile(
            title: Text(AppLocalizations.of(context)!.multiViewsMode),
            trailing: Switch(
              onChanged: (value) {
                setState(() => Prefs.multiTabMode = value);
              },
              value: Prefs.multiTabMode,
            ),
          ),
          if (Prefs.multiTabMode) _getNumTabsVisibleWidget(),
        ],
      ),
    );
  }

  Widget _getNumTabsVisibleWidget() {
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16.0),
          child: Text(AppLocalizations.of(context)!.numVisibleViews),
        ),
        const Spacer(),
        IconButton(
          onPressed: () => setState(() {
            if (Prefs.tabsVisible > 2) Prefs.tabsVisible--;
          }),
          icon: const Icon(Icons.remove),
        ),
        Text(Prefs.tabsVisible.toString()),
        IconButton(
          onPressed: () => setState(() {
            if (Prefs.tabsVisible < 5) Prefs.tabsVisible++;
          }),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }

  Widget _getNewTabAtEndSwitch() {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: Text(AppLocalizations.of(context)!.newTabAtEnd),
        trailing: Switch(
          onChanged: (value) => setState(() => Prefs.isNewTabAtEnd = value),
          value: Prefs.isNewTabAtEnd,
        ),
      ),
    );
  }

  Widget _getExpandedBookListSwitch() {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: const Text("Expanded Booklist"),
        trailing: Switch(
          onChanged: (value) => setState(() => Prefs.expandedBookList = value),
          value: Prefs.expandedBookList,
        ),
      ),
    );
  }

  Widget _getShowTranslationsSwitch() {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: Text(AppLocalizations.of(context)!.showTranslations),
        trailing: Switch(
          onChanged: (value) => setState(() => Prefs.showTranslation = value),
          value: Prefs.showTranslation,
        ),
      ),
    );
  }

  // Color Picker Dialog
  void _openColorPicker(String title, int currentColor, Function(int) onSave) {
    // Cache the localization strings outside the dialog builder to prevent Context errors
    final String cancelText = AppLocalizations.of(context)!.cancel;
    final String okText = AppLocalizations.of(context)!.ok;

    // Internal variable to hold the newly picked color before saving
    int tempSelectedColor = currentColor;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: Color(currentColor),
              onColorChanged: (Color color) {
                tempSelectedColor = color.value;
              },
              pickerAreaHeightPercent: 0.8,
              enableAlpha:
                  false, // Turn off transparency since text usually needs a solid color
            ),
          ),
          actions: [
            TextButton(
              child: Text(cancelText),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: Text(okText),
              onPressed: () {
                // Call the callback to save it and update the main UI
                onSave(tempSelectedColor);
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }
}
