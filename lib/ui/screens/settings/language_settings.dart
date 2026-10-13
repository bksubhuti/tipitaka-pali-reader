import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/language_installer.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/provider/shown_languages_provider.dart';
import 'package:tipitaka_pali/ui/widgets/language_steps.dart';
import 'package:tipitaka_pali/ui/dialogs/translation_terms_dialog.dart';

/// Choosing which translations are installed and the order they read in.
///
/// Order matters and is the reader's own, the way the dictionary list is
/// ordered: Pali always first, then each chosen language beneath it. Dragging
/// a language changes where it appears on the page.
class LanguageSettings extends StatefulWidget {
  const LanguageSettings({super.key});

  @override
  State<LanguageSettings> createState() => _LanguageSettingsState();
}

/// How an installed language compares with the copy on the server.
enum _Freshness { checking, current, newer, unrecorded, offline }

class _LanguageSettingsState extends State<LanguageSettings> {
  String? _busy;

  /// Each installed language against the server, checked when this page
  /// opens: a HEAD request each, nothing downloaded.
  final Map<String, _Freshness> _freshness = {};

  /// The date of the server's copy, where it is newer, and of the device's,
  /// where it is current.
  final Map<String, DateTime?> _dates = {};

  @override
  void initState() {
    super.initState();
    _checkForUpdates();
  }

  Future<void> _checkForUpdates() async {
    final codes = [..._installed];
    setState(() {
      for (final code in codes) {
        _freshness[code] = _Freshness.checking;
      }
    });
    await Future.wait(codes.map((code) async {
      final option = LanguageInstaller.available.firstWhere(
          (o) => o.code == code,
          orElse: () => LanguageOption(code, code));
      final results = await Future.wait([
        LanguageInstaller.deviceCopy(code),
        LanguageInstaller.onlineCopy(option),
      ]);
      final device = results[0];
      final online = results[1];
      final _Freshness freshness;
      DateTime? date;
      if (online == null) {
        freshness = _Freshness.offline;
      } else if (device == null) {
        // Installed before the source was recorded: it cannot be compared.
        freshness = _Freshness.unrecorded;
        date = online.date;
      } else if (device.sameAs(online)) {
        freshness = _Freshness.current;
        date = device.date;
      } else {
        freshness = _Freshness.newer;
        date = online.date;
      }
      if (!mounted) return;
      setState(() {
        _freshness[code] = freshness;
        _dates[code] = date;
      });
    }));
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];

  static String _day(DateTime? date) =>
      date == null ? '' : '${date.day} ${_months[date.month - 1]} ${date.year}';

  /// What the page says about a language's copy, or null for nothing.
  String? _freshnessText(String code) {
    final date = _day(_dates[code]);
    switch (_freshness[code]) {
      case _Freshness.checking:
        return 'Checking for updates…';
      case _Freshness.current:
        return 'Up to date';
      case _Freshness.newer:
        return date.isEmpty ? 'Update available' : 'Update available ($date)';
      case _Freshness.unrecorded:
        return 'Its version was not recorded. Update to get the latest.';
      case _Freshness.offline:
      case null:
        return null;
    }
  }

  bool _canUpdate(String code) =>
      _freshness[code] == _Freshness.newer ||
      _freshness[code] == _Freshness.unrecorded;

  /// Downloads the server's copy over the one on the device. The old copy
  /// keeps working until the new one is whole, and a language switched off
  /// stays off.
  Future<void> _update(String code) async {
    final option =
        LanguageInstaller.available.firstWhere((o) => o.code == code);
    final wasShown = LanguageInstaller.isShown(code);
    final steps = LanguageStepState(LanguageStep.install);
    setState(() {
      _busy = code;
      _steps = steps;
      _stepsTitle = 'Updating ${option.name}';
    });
    try {
      await LanguageInstaller.install(option,
          onStep: (step, fraction, message) {
        if (mounted) setState(() => steps.update(step, fraction, message));
      });
      if (!wasShown) LanguageInstaller.setShown(code, false);
      steps.finish();
      if (mounted) {
        context.read<ShownLanguagesProvider>().installedChanged();
        final device = await LanguageInstaller.deviceCopy(code);
        if (mounted) {
          setState(() {
            _freshness[code] = _Freshness.current;
            _dates[code] = device?.date;
          });
        }
      }
    } catch (e) {
      steps.fail(e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// The install or removal under way, or the last one, until another starts.
  LanguageStepState? _steps;
  String? _stepsTitle;

  static const double _maxWidth = 640;

  List<String> get _installed => DatabaseHelper.installedLanguages;

  /// Every installed language: the ones being shown first, in the order they
  /// appear beneath the Pali, then the ones switched off.
  ///
  /// Switched off is not the same as not installed, so both belong in this
  /// list. Only the shown ones have an order worth keeping.
  List<String> get _ordered {
    // The remembered order covers switched-off languages too, so one does not
    // jump to the bottom of the list the moment it is turned off.
    final order = Prefs.knownLanguages.where(_installed.contains).toList();
    for (final code in Prefs.activeLanguages) {
      if (_installed.contains(code) && !order.contains(code)) order.add(code);
    }
    for (final code in _installed) {
      if (!order.contains(code)) order.add(code);
    }
    return order;
  }

  static String _nameOf(String code) => LanguageInstaller.available
      .firstWhere((o) => o.code == code,
          orElse: () => LanguageOption(code, code.toUpperCase()))
      .name;

  Future<void> _install(LanguageOption option) async {
    if (!await ensureTranslationTermsAccepted(context)) return;
    final steps = LanguageStepState(LanguageStep.install);
    setState(() {
      _busy = option.code;
      _steps = steps;
      _stepsTitle = 'Installing ${option.name}';
    });
    try {
      await LanguageInstaller.install(option,
          onStep: (step, fraction, message) {
        if (mounted) setState(() => steps.update(step, fraction, message));
      });
      steps.finish();
      if (mounted) context.read<ShownLanguagesProvider>().installedChanged();
      final device = await LanguageInstaller.deviceCopy(option.code);
      if (mounted) {
        setState(() {
          _freshness[option.code] = _Freshness.current;
          _dates[option.code] = device?.date;
        });
      }
    } catch (e) {
      steps.fail(e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _remove(String code) async {
    final steps = LanguageStepState(LanguageStep.removal);
    setState(() {
      _busy = code;
      _steps = steps;
      _stepsTitle = 'Removing ${_nameOf(code)}';
    });
    try {
      await LanguageInstaller.remove(code, onStep: (step, fraction, message) {
        if (mounted) setState(() => steps.update(step, fraction, message));
      });
      steps.finish();
      if (mounted) context.read<ShownLanguagesProvider>().installedChanged();
    } catch (e) {
      steps.fail(e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<bool> _confirmLeave() async {
    final removing = _stepsTitle?.startsWith('Removing') ?? false;
    final leave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: Colors.orange, size: 48),
        title: Text(removing ? 'Removal in progress' : 'Install in progress'),
        content: Text(
          '${_stepsTitle ?? 'A translation'} is still under way.\n\n'
          'If you leave, it carries on without showing its progress. '
          'Quitting the app stops it; nothing is damaged, and it can be '
          '${removing ? 'removed' : 'installed'} again afterwards.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave anyway'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final ordered = _ordered;
    // Leaving mid-install is safe, since nothing is given its real name
    // until it is whole, but the steps go out of sight and a second install
    // could be started over the first. So it asks, as the extension
    // download does.
    return PopScope(
      canPop: _busy == null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && mounted) Navigator.of(this.context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Translations')),
        // On a wide window the list keeps to a readable width, centred. Full
        // width put each language's name far across the window from its
        // switch and buttons. The padding, not a narrower list, does it, so
        // the whole window still scrolls it.
        body: LayoutBuilder(
          builder: (context, constraints) => ListView(
            padding: EdgeInsets.symmetric(
                horizontal: constraints.maxWidth > _maxWidth
                    ? (constraints.maxWidth - _maxWidth) / 2
                    : 0),
            children: [
              if (_steps != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 16, 16, 0),
                  child: Text(_stepsTitle ?? '',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                LanguageSteps(state: _steps!),
              ],
              if (ordered.isNotEmpty) ...[
                const _Heading('Installed'),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Switch a translation off to read the Pali alone. '
                    'It stays on the device, so turning it back on costs nothing. '
                    'Drag to change the order they appear in.',
                  ),
                ),
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  // Our own handle, on the left. The default one added a second
                  // handle on the right on desktop.
                  buildDefaultDragHandles: false,
                  onReorder: (oldIndex, newIndex) {
                    final list = [...ordered];
                    if (newIndex > oldIndex) newIndex -= 1;
                    list.insert(newIndex, list.removeAt(oldIndex));
                    setState(() {
                      // The full order, including the ones switched off, and the
                      // reader's own list narrowed to what is shown.
                      Prefs.knownLanguages = list;
                      Prefs.activeLanguages =
                          list.where(LanguageInstaller.isShown).toList();
                    });
                    context.read<ShownLanguagesProvider>().reordered();
                  },
                  children: [
                    for (final (index, code) in ordered.indexed)
                      _RowCard(
                        key: ValueKey(code),
                        index: index,
                        child: ListTile(
                          leading: ReorderableDragStartListener(
                            index: index,
                            child: const Icon(Icons.drag_handle),
                          ),
                          title: Text(_nameOf(code)),
                          // The switch says whether it is shown; this says
                          // only whether there is a newer copy.
                          subtitle: switch (_freshnessText(code)) {
                            final text?
                                when _freshness[code] == _Freshness.current =>
                              Text.rich(TextSpan(children: [
                                TextSpan(text: '$text '),
                                const WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: Icon(Icons.check_circle,
                                      size: 16, color: Colors.green),
                                ),
                              ])),
                            final text? => Text(
                                text,
                                style: _canUpdate(code)
                                    ? TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontWeight: FontWeight.w600)
                                    : null,
                              ),
                            null => null,
                          },
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: context
                                    .watch<ShownLanguagesProvider>()
                                    .isShown(code),
                                onChanged: _busy == code
                                    ? null
                                    : (on) => setState(() => context
                                        .read<ShownLanguagesProvider>()
                                        .setLanguageShown(code, on)),
                              ),
                              if (_busy != code && _canUpdate(code))
                                IconButton(
                                  icon: const Icon(Icons.system_update_alt),
                                  tooltip: 'Update',
                                  onPressed: _busy == null
                                      ? () => _update(code)
                                      : null,
                                ),
                              if (_busy != code)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: 'Remove from the device',
                                  onPressed: () => _remove(code),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const _Heading('Available to install'),
              for (final option in LanguageInstaller.available)
                if (!_installed.contains(option.code))
                  _RowCard(
                    child: ListTile(
                      title: Text(option.name),
                      trailing: _busy == option.code
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : IconButton(
                              icon: const Icon(Icons.download_outlined),
                              tooltip: 'Install',
                              onPressed:
                                  _busy == null ? () => _install(option) : null,
                            ),
                    ),
                  ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Translations come from the ePitaka project. They are produced '
                  'with machine assistance and each sentence carries a confidence '
                  'rating, so they are a reading aid rather than a published '
                  'translation.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The entry in the settings list that opens the page above.
class TranslationSettingsView extends StatelessWidget {
  const TranslationSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final installed = DatabaseHelper.installedLanguages;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.translate_outlined),
        title:
            Text('Translations', style: Theme.of(context).textTheme.titleLarge),
        subtitle: Text(installed.isEmpty
            ? 'None installed'
            : installed.map(_LanguageSettingsState._nameOf).join(', ')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LanguageSettings()),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

/// One language as a card, so each row stands apart from the page.
///
/// With an [index], the row sits in the reorderable list, and a long press
/// anywhere on it picks it up, as the list did before it had its own handle.
class _RowCard extends StatelessWidget {
  final int? index;
  final Widget child;
  const _RowCard({super.key, this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    final card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: child,
    );
    if (index == null) return card;
    return ReorderableDelayedDragStartListener(index: index!, child: card);
  }
}
