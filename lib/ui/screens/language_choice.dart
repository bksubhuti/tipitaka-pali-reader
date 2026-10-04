import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:tipitaka_pali/services/language_installer.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/provider/shown_languages_provider.dart';
import 'package:tipitaka_pali/ui/widgets/language_steps.dart';
import 'package:tipitaka_pali/ui/dialogs/translation_terms_dialog.dart';

/// Offered once, when the app first has the sentence data to use it, and
/// again after a reset.
///
/// A reset starts a fresh database but leaves the language files where they
/// are, so a language can already be on the device here. It is shown as
/// such, and choosing it asks whether to use that copy or download it again,
/// saying whether it is the same as the one online.
///
/// A translation is optional. The Pali is what the app is for, so the choice
/// is presented plainly and declining is a normal answer, not a smaller
/// button. Whatever is chosen here can be changed later in settings.
class LanguageChoiceScreen extends StatefulWidget {
  const LanguageChoiceScreen({super.key});

  @override
  State<LanguageChoiceScreen> createState() => _LanguageChoiceScreenState();
}

class _LanguageChoiceScreenState extends State<LanguageChoiceScreen> {
  String? _installing;
  LanguageStepState? _steps;
  bool _done = false;

  /// The language whose copy on the device is being compared with the one
  /// online.
  String? _checking;

  /// Uses the copy on the device, or downloads it again, as the reader says.
  Future<void> _offerDeviceCopy(LanguageOption option) async {
    setState(() => _checking = option.code);
    final online = await LanguageInstaller.onlineCopy(option);
    final device = await LanguageInstaller.deviceCopy(option.code);
    final installed = LanguageInstaller.installedOn(option.code);
    if (!mounted) return;
    setState(() => _checking = null);

    String day(DateTime? date) =>
        date == null ? 'an unknown date' : DateFormat.yMMMd().format(date);
    final name = option.name;
    final String message;
    var useFirst = true;
    if (online == null) {
      message = '$name is already on this device, installed '
          '${day(installed)}. The one online could not be checked, so it '
          'is not known whether a newer one is there.';
    } else if (device == null) {
      message = '$name is already on this device, installed '
          '${day(installed)}. It cannot be compared with the one online, '
          'which is from ${day(online.date)}.';
    } else if (device.sameAs(online)) {
      message = 'The $name on this device is the same as the one online, '
          'from ${day(online.date)}. There is no need to download it again.';
    } else {
      message = 'The $name on this device is from ${day(device.date)}. '
          'A different one is online, from ${day(online.date)}.';
      useFirst = false;
    }

    final download = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$name is on this device'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(useFirst ? 'Download again' : 'Download the new one'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Use this one'),
          ),
        ],
      ),
    );
    if (download == null || !mounted) return;
    if (download) {
      await _install(option);
    } else {
      await _useDeviceCopy(option);
    }
  }

  Future<void> _useDeviceCopy(LanguageOption option) async {
    final steps = LanguageStepState(LanguageStep.install);
    setState(() {
      _installing = option.code;
      _steps = steps;
    });
    try {
      await LanguageInstaller.useLocal(option.code,
          onStep: (step, fraction, message) {
        if (mounted) setState(() => steps.update(step, fraction, message));
      });
      steps.finish();
      if (mounted) {
        context.read<ShownLanguagesProvider>().installedChanged();
        setState(() => _done = true);
      }
    } catch (e) {
      steps.fail('Could not use ${option.name}. $e');
    } finally {
      if (mounted) setState(() => _installing = null);
    }
  }

  Future<void> _install(LanguageOption option) async {
    if (!await ensureTranslationTermsAccepted(context)) return;
    final steps = LanguageStepState(LanguageStep.install);
    setState(() {
      _installing = option.code;
      _steps = steps;
    });
    try {
      await LanguageInstaller.install(option,
          onStep: (step, fraction, message) {
        if (mounted) setState(() => steps.update(step, fraction, message));
      });
      steps.finish();
      if (mounted) {
        context.read<ShownLanguagesProvider>().installedChanged();
        setState(() => _done = true);
      }
    } catch (e) {
      steps.fail('Could not install ${option.name}. $e');
    } finally {
      if (mounted) setState(() => _installing = null);
    }
  }

  void _finish() {
    Prefs.languageChoiceMade = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _installing != null || _checking != null;
    final anyInstalled = LanguageInstaller.available
        .any((o) => LanguageInstaller.isInstalled(o.code));

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          // On a wide window the choice keeps to a readable width, centred.
          // Full width put each language's name far across the window from
          // its download button.
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Translations',
                            style: theme.textTheme.headlineSmall),
                        const SizedBox(height: 12),
                        const Text(
                          'A translation can be shown beneath the Pali. You can '
                          'choose one now, add more later in settings, or read '
                          'the Pali on its own.',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Translations come from the ePitaka project. They are '
                          'produced with machine assistance, so they are a reading '
                          'aid rather than a published translation.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (_steps != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: LanguageSteps(state: _steps!),
                    ),
                  Expanded(
                    child: _done
                        ? const Center(child: Icon(Icons.check, size: 48))
                        : ListView(
                            children: [
                              for (final option in LanguageInstaller.available)
                                Card(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 4),
                                  child: _languageTile(option, busy),
                                ),
                            ],
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: busy ? null : _finish,
                        child: Text(_done || anyInstalled
                            ? 'Continue'
                            : 'Read Pali only'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _languageTile(LanguageOption option, bool busy) {
    final onDevice = LanguageInstaller.isInstalled(option.code);
    final working = _installing == option.code || _checking == option.code;
    return ListTile(
      title: Text(option.name),
      subtitle: onDevice ? const Text('On this device') : null,
      enabled: !busy,
      trailing: working
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(
              onDevice ? Icons.check_circle_outline : Icons.download_outlined),
      onTap: busy
          ? null
          : () => onDevice ? _offerDeviceCopy(option) : _install(option),
    );
  }
}
