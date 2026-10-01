import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:tipitaka_pali/services/language_installer.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/provider/shown_languages_provider.dart';
import 'package:tipitaka_pali/ui/widgets/language_steps.dart';

/// Offered once, when the app first has the sentence data to use it.
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

  Future<void> _install(LanguageOption option) async {
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
    final busy = _installing != null;

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
                      padding: const EdgeInsets.symmetric(horizontal: 24),
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
                                  child: ListTile(
                                    title: Text(option.name),
                                    enabled: !busy,
                                    trailing: _installing == option.code
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2))
                                        : const Icon(Icons.download_outlined),
                                    onTap: busy ? null : () => _install(option),
                                  ),
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
                        child: Text(_done ? 'Continue' : 'Read Pali only'),
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
}
