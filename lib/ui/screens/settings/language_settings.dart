import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:tipitaka_pali/l10n/app_localizations.dart';
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

/// What the steps on the page are doing.
enum _Task { install, update, removal }

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

  /// The date as "3 Oct 2026", with the month named in the app's language.
  String _day(DateTime? date) {
    if (date == null) return '';
    try {
      return DateFormat('d MMM y', AppLocalizations.of(context)!.localeName)
          .format(date);
    } catch (_) {
      return DateFormat('d MMM y', 'en').format(date);
    }
  }

  /// What the page says about a language's copy, or null for nothing.
  String? _freshnessText(String code) {
    final l = AppLocalizations.of(context)!;
    final date = _day(_dates[code]);
    switch (_freshness[code]) {
      case _Freshness.checking:
        return l.checkingForUpdates;
      case _Freshness.current:
        return l.upToDate;
      case _Freshness.newer:
        return date.isEmpty ? l.updateAvailable : l.updateAvailableOn(date);
      case _Freshness.unrecorded:
        return l.versionNotRecorded;
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
      _task = _Task.update;
      _taskLanguage = option.name;
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
  _Task? _task;
  String _taskLanguage = '';

  /// "Installing English" and the like, over the steps.
  String _stepsTitle(AppLocalizations l) => switch (_task) {
        _Task.install => l.installingLanguage(_taskLanguage),
        _Task.update => l.updatingLanguage(_taskLanguage),
        _Task.removal => l.removingLanguage(_taskLanguage),
        null => '',
      };

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
      _task = _Task.install;
      _taskLanguage = option.name;
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
      _task = _Task.removal;
      _taskLanguage = _nameOf(code);
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
    final leave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => LeaveInProgressDialog(
        removing: _task == _Task.removal,
        task: _stepsTitle(AppLocalizations.of(dialogContext)!),
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final ordered = _ordered;
    final l = AppLocalizations.of(context)!;
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
        appBar: AppBar(title: Text(l.translations)),
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
                  child: Text(_stepsTitle(l),
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                LanguageSteps(state: _steps!),
              ],
              if (ordered.isNotEmpty) ...[
                _Heading(l.installedHeading),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(l.translationsSwitchHelp),
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
                        child: LanguageRowTile(
                          index: index,
                          name: _nameOf(code),
                          status: _freshnessText(code),
                          current: _freshness[code] == _Freshness.current,
                          canUpdate: _canUpdate(code),
                          shown: context
                              .watch<ShownLanguagesProvider>()
                              .isShown(code),
                          busy: _busy == code,
                          onShownChanged: (on) => setState(() => context
                              .read<ShownLanguagesProvider>()
                              .setLanguageShown(code, on)),
                          onUpdate: _busy == null ? () => _update(code) : null,
                          onRemove: () => _remove(code),
                        ),
                      ),
                  ],
                ),
              ],
              _Heading(l.availableToInstall),
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
                              tooltip: l.install,
                              onPressed:
                                  _busy == null ? () => _install(option) : null,
                            ),
                    ),
                  ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l.translationsSourceNote),
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
    final l = AppLocalizations.of(context)!;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.translate_outlined),
        title:
            Text(l.translations, style: Theme.of(context).textTheme.titleLarge),
        subtitle: Text(installed.isEmpty
            ? l.noneInstalled
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

/// One installed language: its name, whether there is a newer copy, the
/// switch that shows it, and the buttons that update and remove it.
///
/// [index] is its place in the reorderable list, for the drag handle. While
/// it is [busy] the switch is off limits and the buttons are hidden.
class LanguageRowTile extends StatelessWidget {
  final int index;
  final String name;

  /// What is known of the server's copy, or null for nothing.
  final String? status;

  /// The device's copy is the server's: the status gets a tick.
  final bool current;

  /// There is a newer copy: the status stands out and the update button shows.
  final bool canUpdate;

  final bool shown;
  final bool busy;
  final ValueChanged<bool> onShownChanged;

  /// Null while something else is being installed or removed.
  final VoidCallback? onUpdate;
  final VoidCallback onRemove;

  const LanguageRowTile({
    super.key,
    required this.index,
    required this.name,
    required this.status,
    required this.current,
    required this.canUpdate,
    required this.shown,
    required this.busy,
    required this.onShownChanged,
    required this.onUpdate,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ListTile(
      leading: ReorderableDragStartListener(
        index: index,
        child: const Icon(Icons.drag_handle),
      ),
      title: Text(name),
      // The switch says whether it is shown; this says only whether there is
      // a newer copy.
      subtitle: switch (status) {
        final text? when current => Text.rich(TextSpan(children: [
            TextSpan(text: '$text '),
            const WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(Icons.check_circle, size: 16, color: Colors.green),
            ),
          ])),
        final text? => Text(
            text,
            style: canUpdate
                ? TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600)
                : null,
          ),
        null => null,
      },
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: shown,
            onChanged: busy ? null : onShownChanged,
          ),
          if (!busy && canUpdate)
            IconButton(
              icon: const Icon(Icons.system_update_alt),
              tooltip: l.update,
              onPressed: onUpdate,
            ),
          if (!busy)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l.removeFromDevice,
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}

/// Asks whether to leave the page while [task] (an install, an update or,
/// if [removing], a removal) is still running. Pops true to leave.
class LeaveInProgressDialog extends StatelessWidget {
  final bool removing;

  /// "Installing English" and the like.
  final String task;

  const LeaveInProgressDialog(
      {super.key, required this.removing, required this.task});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded,
          color: Colors.orange, size: 48),
      title: Text(removing ? l.removalInProgress : l.installInProgress),
      content: Text(
          removing ? l.leaveRemovalMessage(task) : l.leaveInstallMessage(task)),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.stay),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.leaveAnyway),
        ),
      ],
    );
  }
}
