import 'package:flutter/material.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/update_check.dart';

/// On the home screen, a small blue button to the store page when a newer
/// build is out, as VS Code shows one; nothing otherwise.
class UpdateButton extends StatefulWidget {
  const UpdateButton({super.key});

  @override
  State<UpdateButton> createState() => _UpdateButtonState();
}

class _UpdateButtonState extends State<UpdateButton> {
  @override
  void initState() {
    super.initState();
    UpdateCheck.start();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Uri?>(
      valueListenable: UpdateCheck.storePage,
      builder: (context, page, _) {
        if (page == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0078D4),
                  foregroundColor: Colors.white,
                  elevation: 3,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                ),
                icon: const Icon(Icons.system_update_alt, size: 18),
                label: Text(AppLocalizations.of(context)!.updateAvailable),
                onPressed: () =>
                    launchUrl(page, mode: LaunchMode.externalApplication),
              ),
              // Away until a newer build is out.
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: AppLocalizations.of(context)!.close,
                visualDensity: VisualDensity.compact,
                onPressed: UpdateCheck.dismiss,
              ),
            ],
          ),
        );
      },
    );
  }
}
