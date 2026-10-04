import 'package:flutter/material.dart';

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
    builder: (dialogContext) => AlertDialog(
      title: const Text('ePitaka AI Translations'),
      content: const SingleChildScrollView(
        child: Text(
          'These translations are from Epitaka.org. They were made by AI '
          '(2026), using Myanmar Nissaya data provided by Wikipali.org.\n\n'
          'They can contain mistakes. Use them with discretion, and check '
          'the Pāḷi where it matters.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('I Agree'),
        ),
      ],
    ),
  );

  if (agreed != true) return false;
  Prefs.translationTermsAccepted = true;
  return true;
}
