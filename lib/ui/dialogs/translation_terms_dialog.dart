import 'package:flutter/material.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';

import '../../services/prefs.dart';

/// Asks the reader to agree to the terms of the ePitaka translations before
/// the first one is downloaded.
///
/// Asked once for the life of the preferences: true straight away once
/// agreed. Returns false if the reader does not agree, and the download does
/// not go ahead.
Future<bool> ensureTranslationTermsAccepted(BuildContext context) async {
  if (Prefs.translationTermsAccepted) return true;

  final agreed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const TranslationTermsDialog(),
  );

  if (agreed != true) return false;
  Prefs.translationTermsAccepted = true;
  return true;
}

/// The terms themselves. Pops true when the reader agrees.
class TranslationTermsDialog extends StatelessWidget {
  const TranslationTermsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l.translationTermsTitle),
      content: SingleChildScrollView(child: Text(l.translationTermsMessage)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.iAgree),
        ),
      ],
    );
  }
}
