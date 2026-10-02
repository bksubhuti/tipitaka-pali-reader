import 'package:flutter/material.dart';

import 'package:tipitaka_pali/services/language_installer.dart';
import 'package:tipitaka_pali/ui/widgets/step_progress.dart';

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
    // Drawn the way first-run setup draws its steps, so the two match.
    final current =
        state.current == null ? 0 : state.steps.indexOf(state.current!);
    return StepProgress(
      titles: [for (final step in state.steps) step.label],
      completed: current < 0 ? 0 : current,
      finished: state.finished,
      status: state.message,
      fraction: state.fraction,
      error: state.error,
    );
  }
}
