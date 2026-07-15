import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';

void showAiHelpDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(AppLocalizations.of(context)!.howToGetApiKey),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.ondemand_video),
                label: const Text('Watch Key Instructions'),
                onPressed: () async {
                  final url =
                      Uri.parse('https://www.youtube.com/watch?v=zgmkYP7UqtU');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ),
            const SizedBox(height: 24),
            Text(AppLocalizations.of(context)!.apiKeyInstructions1),
            const SizedBox(height: 12),
            Text(AppLocalizations.of(context)!.apiKeyInstructions2),
            Text(AppLocalizations.of(context)!.apiKeyInstructions3),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(AppLocalizations.of(context)!.close),
        ),
        ElevatedButton(
          child: Text(AppLocalizations.of(context)!.getGenminiKey),
          onPressed: () async {
            final url = Uri.parse('https://aistudio.google.com/app/apikey');
            if (await canLaunchUrl(url)) {
              await launchUrl(url);
            }
          },
        ),
      ],
    ),
  );
}
