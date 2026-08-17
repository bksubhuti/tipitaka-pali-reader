import 'dart:io';

import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/business_logic/view_models/initial_setup_service.dart';
import 'package:tipitaka_pali/providers/initial_setup_notifier.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/ui/dialogs/extension_prompt_dialog.dart';
import 'package:tipitaka_pali/ui/screens/settings/download_view.dart';
import 'package:tipitaka_pali/ui/widgets/colored_text.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../dialogs/reset_dialog.dart';

class InitialSetup extends StatefulWidget {
  final bool isUpdateMode;
  const InitialSetup({super.key, this.isUpdateMode = false});

  @override
  State<InitialSetup> createState() => _InitialSetupState();
}

class _InitialSetupState extends State<InitialSetup> {
  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initialSetupNotifier =
        Provider.of<InitialSetupNotifier>(context, listen: false);
    final initialSetupService =
        InitialSetupService(context, initialSetupNotifier, widget.isUpdateMode);
    initialSetupService.setUp(widget.isUpdateMode);

    return Material(
      // NOTE by Rydmike: Annotated region example for
      // Android: No AppBar status scrim and no sys nav scrim.
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: FlexColorScheme.themedSystemNavigationBar(
          context,
          noAppBar: true,
          systemNavBarStyle: FlexSystemNavBarStyle.transparent,
          useDivider: false,
        ),
        child: ChangeNotifierProvider.value(
          value: initialSetupNotifier,
          child: Center(
            child: _buildHomeView(context, initialSetupNotifier),
          ),
        ),
      ),
    );
  }

  Widget _buildHomeView(BuildContext context, InitialSetupNotifier notifier) {
    if (notifier.setupIsFinished) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        concludeTheSetup(context);
      });
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          child: Text(AppLocalizations.of(context)!.resetData),
          onPressed: () {
            doResetDialog(context);
          },
        ),
        const SizedBox(height: 20),
        Ink.image(
          height: 100,
          width: 100,
          image: const AssetImage('assets/icon/icon.png'),
          fit: BoxFit.scaleDown,
        ),
        const SizedBox(height: 20),
/*        const Text(
          "Set Language \nသင်၏ဘာသာစကားကိုရွေးပါ\nඔබේ භාෂාව තෝරන්න\n选择你的语言\nChọn ngôn ngữ\nभाषा चयन करें\n",
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        SelectLanguageWidget(),
        const SizedBox(height: 20),
        const SelectScriptLanguageWidget(),
        const SizedBox(height: 20),
        */
        const CircularProgressIndicator(),
        const SizedBox(height: 10),
        widget.isUpdateMode
            ? Text(
                AppLocalizations.of(context)!.updatingStatus,
                textAlign: TextAlign.center,
              )
            : Text(
                AppLocalizations.of(context)!.copyingStatus,
                textAlign: TextAlign.center,
              ),
        const SizedBox(height: 10),
        Consumer<InitialSetupNotifier>(
          builder: (context, notifier, child) {
            return _buildVerticalStepProgress(context, notifier);
          },
        ),
        const SizedBox(height: 20),
        Consumer<InitialSetupNotifier>(
          builder: (context, notifier, _) {
            if (notifier.setupIsFinished) {
              notifier.setupIsFinished = false;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                concludeTheSetup(context);
              });
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }

  Widget _buildVerticalStepProgress(
      BuildContext context, InitialSetupNotifier notifier) {
    final stepTitles = [
      'Copying Core Database',
      'Building Word List Index',
      'Building Book Indexes',
    ];

    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(stepTitles.length, (index) {
          final isDone = notifier.stepsCompleted > index;
          final isActive =
              notifier.stepsCompleted == index && !notifier.setupIsFinished;
          final isLast = index == stepTitles.length - 1;

          Color circleColor;
          Widget circleChild;

          if (isDone) {
            circleColor = Colors.green;
            circleChild =
                const Icon(Icons.check, size: 14, color: Colors.white);
          } else if (isActive) {
            circleColor = Colors.blue;
            circleChild = Text(
              '${index + 1}',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12),
            );
          } else {
            circleColor = Colors.grey.shade400;
            circleChild = Text(
              '${index + 1}',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12),
            );
          }

          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: circleColor,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: circleChild,
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: isDone ? Colors.green : Colors.grey.shade300,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 16.0, top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stepTitles[index],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isActive || isDone
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isActive
                                ? Colors.blue
                                : (isDone
                                    ? Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.color
                                    : Theme.of(context).disabledColor),
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.blue),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  notifier.status,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  void concludeTheSetup(BuildContext context) async {
    List<File> extensions = getExtensionFiles();

    // --- THE GATEKEEPER ---
    // Check if the JSON mapping cache exists
    final cacheFile = File('${Prefs.databaseDirPath}/download_list_cache.json');
    final hasJsonCache = await cacheFile.exists();

    if (extensions.isNotEmpty && hasJsonCache) {
      String exlist = "";
      for (final file in extensions) {
        final fileName = path.basename(file.path);
        exlist += "$fileName\n";
      }

      final message =
          "${AppLocalizations.of(context)!.folloingExtensions}\n$exlist \n ${AppLocalizations.of(context)!.wouldYouLikeToInstall}";

      // Prompt the user to install extensions
      final shouldInstall = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return ExtensionPromptDialog(message: message);
        },
      );

      if (shouldInstall ?? false) {
        // User selected Yes
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const DownloadView(showLocalRestores: true),
          ),
        ).then((_) {
          _openHomePage(context);
        });
        return;
      }
    }

    // Prompt user for English Translation Extension if not installed
    final isInstalled = await _isEnglishExtensionInstalled();
    if (!isInstalled && context.mounted) {
      final shouldInstall = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title:
                Text(AppLocalizations.of(context)!.installEnglishTranslations),
            content: Text(
                AppLocalizations.of(context)!.installTranslationInstructions),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Later'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Install Now'),
              ),
            ],
          );
        },
      );

      if ((shouldInstall ?? false) && context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const DownloadView(autoInstallEnglish: true),
          ),
        ).then((_) {
          _openHomePage(context);
        });
        return;
      }
    }

    _openHomePage(context);
  }

  Future<bool> _isEnglishExtensionInstalled() async {
    try {
      final db = await DatabaseHelper().database;
      final res =
          await db.rawQuery('SELECT count(*) cnt FROM fts_translation_pages');
      final count = (res.first['cnt'] as int?) ?? 0;
      return count > 0;
    } catch (_) {
      return false;
    }
  }

  void _openHomePage(context) {
    //Navigator.of(context).pop();
    Navigator.of(context).pushNamed('/home');
  }

  List<File> getExtensionFiles() {
    final directory = Directory(Prefs.databaseDirPath);
    if (!directory.existsSync()) return [];
    final files = directory.listSync().whereType<File>().toList();
    List<File> extensions = [];

    const legacyZips = {
      'full_en.zip',
      'full_vn.zip',
      'en_full.zip',
      'vn_full.zip',
    };

    for (final file in files) {
      final nameLower = path.basename(file.path).toLowerCase();
      if (nameLower.endsWith('.zip') && !legacyZips.contains(nameLower)) {
        extensions.add(file);
      }
    }
    return extensions;
  }
}
