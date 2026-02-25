import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
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
          _getTextDisplayModeRadio(), // <--- The new Radio Button group
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
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _getTextDisplayModeRadio() {
    // WATCH: So the UI updates when mode or bold setting changes
    final currentMode = context.watch<ThemeChangeNotifier>().textDisplayMode;
    final isPaliBold = context.watch<ThemeChangeNotifier>().isPaliBold;

    return Padding(
      padding: const EdgeInsets.only(left: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16.0, top: 8.0, bottom: 8.0),
            child: Text(
              "Text Display Mode",
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          RadioGroup<TextDisplayMode>(
            groupValue: currentMode,
            onChanged: (TextDisplayMode? value) {
              if (value != null) {
                context
                    .read<ThemeChangeNotifier>()
                    .onChangeTextDisplayMode(value);
              }
            },
            child: Column(
              children: [
                RadioListTile<TextDisplayMode>(
                  title: const Text('Pāḷi Only'),
                  value: TextDisplayMode.paliOnly,
                ),
                RadioListTile<TextDisplayMode>(
                  title: const Text('Pāḷi & Translation'),
                  value: TextDisplayMode.paliAndTranslation,
                ),
                RadioListTile<TextDisplayMode>(
                  title: const Text('Translation Only'),
                  value: TextDisplayMode.translationOnly,
                ),
              ],
            ),
          ),

          // NEW: Bold Checkbox!
          // Only show this checkbox if Pāḷi text is actually on the screen
          if (currentMode != TextDisplayMode.translationOnly)
            Padding(
              padding: const EdgeInsets.only(
                  left: 16.0), // Indent it slightly under the radio buttons
              child: CheckboxListTile(
                title: const Text('Bold Pāḷi Text'),
                value: isPaliBold,
                onChanged: (bool? value) {
                  if (value != null) {
                    context
                        .read<ThemeChangeNotifier>()
                        .onChangeIsPaliBold(value);
                  }
                },
                controlAffinity: ListTileControlAffinity
                    .leading, // Puts the checkbox on the left
                contentPadding:
                    EdgeInsets.zero, // Keeps it tight with the radio buttons
              ),
            ),
        ],
      ),
    );
  }

  Widget _getPaliTextColorSetting() {
    // WATCH: Rebuilds the little color circle so it changes instantly
    final currentPaliColor = context.watch<ThemeChangeNotifier>().paliTextColor;

    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        title: Text(AppLocalizations.of(context)!.paliTextColor),
        trailing: _colorIndicator(Color(currentPaliColor)),
        onTap: () => _openColorPicker(
          AppLocalizations.of(context)!.paliTextColor,
          currentPaliColor,
          (colorValue) {
            // READ: Saves the color and notifies listeners
            context
                .read<ThemeChangeNotifier>()
                .onChangePaliTextColor(colorValue);
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
            // READ: Saves the color and notifies listeners
            context
                .read<ThemeChangeNotifier>()
                .onChangeTranslationColor(colorValue);
          },
        ),
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

  void _openColorPicker(String title, int currentColor, Function(int) onSave) {
    final String cancelText = AppLocalizations.of(context)!.cancel;
    final String okText = AppLocalizations.of(context)!.ok;

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
              enableAlpha: false,
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
