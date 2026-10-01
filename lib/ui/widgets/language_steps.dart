import 'package:flutter/material.dart';

import 'package:tipitaka_pali/services/language_installer.dart';

/// Where an install or a removal has got to.
///
/// Held by the screen and fed from the installer's [LanguageProgress]
/// callback, so both the first-run screen and settings show the same thing.
class LanguageStepState {
  final List<LanguageStep> steps;
  LanguageStep? current;
  double? fraction;
  String message = '';
  String? error;
  bool finished = false;

  LanguageStepState(this.steps);

  void update(LanguageStep step, double? fraction, String message) {
    current = step;
    this.fraction = fraction;
    this.message = message;
  }

  void fail(Object e) => error = '$e';

  void finish() {
    finished = true;
    fraction = null;
  }
}

/// The stages of a language install, ticked off as they finish.
///
/// One line that said "Reloading…" for minutes gave no way to tell working
/// from stuck. Each stage here is named, the current one says what it is
/// doing, and the download shows how far it has got.
class LanguageSteps extends StatelessWidget {
  final LanguageStepState state;
  const LanguageSteps({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentIndex =
        state.current == null ? -1 : state.steps.indexOf(state.current!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < state.steps.length; i++)
          _row(context, state.steps[i], i, currentIndex),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(state.error!,
                style: TextStyle(color: theme.colorScheme.error)),
          ),
      ],
    );
  }

  Widget _row(
      BuildContext context, LanguageStep step, int index, int currentIndex) {
    final theme = Theme.of(context);
    final done = state.finished || index < currentIndex;
    final active = !state.finished && index == currentIndex;
    final failed = active && state.error != null;

    Widget icon;
    if (failed) {
      icon = Icon(Icons.error_outline, color: theme.colorScheme.error);
    } else if (done) {
      icon = Icon(Icons.check_circle, color: theme.colorScheme.primary);
    } else if (active) {
      icon = const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2));
    } else {
      icon = Icon(Icons.radio_button_unchecked, color: theme.disabledColor);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 24, height: 24, child: Center(child: icon)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.label,
                    style: TextStyle(
                        fontWeight: active ? FontWeight.bold : null,
                        color: done || active ? null : theme.disabledColor)),
                if (active && state.message.isNotEmpty && !failed)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(state.message,
                        style: theme.textTheme.bodySmall),
                  ),
                if (active && state.fraction != null && !failed)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: LinearProgressIndicator(value: state.fraction),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
