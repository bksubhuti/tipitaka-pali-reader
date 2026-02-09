import 'package:flutter/material.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:tipitaka_pali/routes.dart';
import 'package:tipitaka_pali/ui/screens/dictionary/flashcard_setup_view.dart';
import 'package:tipitaka_pali/ui/screens/dictionary/text_converter_view.dart';
import 'package:tipitaka_pali/ui/screens/settings/book_import_view.dart';
import 'package:tipitaka_pali/ui/screens/settings/download_view.dart';
import 'package:tipitaka_pali/ui/widgets/colored_text.dart';

class ToolsSettingsView extends StatefulWidget {
  final ScrollController scrollController;

  const ToolsSettingsView({super.key, required this.scrollController});

  @override
  State<ToolsSettingsView> createState() => _ToolsSettingsViewState();
}

class _ToolsSettingsViewState extends State<ToolsSettingsView> {
  final GlobalKey expansionTileKey = GlobalKey(); // Declare a GlobalKey

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        key: expansionTileKey, // Assign the key to the ExpansionTile
        leading: const Icon(Icons.build),
        title: Text(AppLocalizations.of(context)!.tools,
            style: Theme.of(context).textTheme.titleLarge),
        onExpansionChanged: (expanded) {
          if (expanded) {
            // Scroll to the end of the list
            Future.delayed(const Duration(milliseconds: 200)).then((_) {
              RenderObject? renderObject =
                  expansionTileKey.currentContext?.findRenderObject();
              renderObject?.showOnScreen(
                rect: renderObject.semanticBounds,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOut,
              );
            });
          }
        },
        children: [
          const SizedBox(
            height: 10,
          ),
          _getExtensionsTile(context),
          _getImportTile(context),
          _getFlashCardExportTile(context),
          _getTextConverterTile(context),
        ],
      ),
    );
  }

  Widget _getExtensionsTile(context) {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        onTap: () {
          final route =
              MaterialPageRoute(builder: (context) => const DownloadView());
          NestedNavigationHelper.goto(
              context: context, route: route, navkey: settingNavigationKey);
        },
        leading: const Icon(Icons.extension),
        title: ColoredText(
          AppLocalizations.of(context)!.extensions,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        focusColor: Theme.of(context).focusColor,
        hoverColor: Theme.of(context).hoverColor,
        trailing: const Icon(Icons.navigate_next),
      ),
    );
  }

  Widget _getImportTile(context) {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        onTap: () {
          final route =
              MaterialPageRoute(builder: (context) => const BookImportView());
          NestedNavigationHelper.goto(
              context: context, route: route, navkey: settingNavigationKey);
        },
        leading: const Icon(Icons.upload),
        title: ColoredText(
          "Import",
          style: Theme.of(context).textTheme.titleLarge,
        ),
        focusColor: Theme.of(context).focusColor,
        hoverColor: Theme.of(context).hoverColor,
        trailing: const Icon(Icons.navigate_next),
      ),
    );
  }

  Widget _getFlashCardExportTile(context) {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        leading: const Icon(Icons.speaker_notes_outlined),
        title: ColoredText(
          AppLocalizations.of(context)!.flashcards,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        focusColor: Theme.of(context).focusColor,
        hoverColor: Theme.of(context).hoverColor,
        trailing: const Icon(Icons.navigate_next),
        onTap: () {
          final route = MaterialPageRoute(
              builder: (context) => const FlashCardSetupView());
          NestedNavigationHelper.goto(
              context: context, route: route, navkey: settingNavigationKey);
        },
      ),
    );
  }

  Widget _getTextConverterTile(context) {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ListTile(
        onTap: () {
          final route = MaterialPageRoute(
              builder: (context) => const TextConverterView());
          NestedNavigationHelper.goto(
              context: context, route: route, navkey: settingNavigationKey);
        },
        leading: const Icon(Icons.translate),
        title: ColoredText(
          AppLocalizations.of(context)!.scriptConverter,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        focusColor: Theme.of(context).focusColor,
        hoverColor: Theme.of(context).hoverColor,
        trailing: const Icon(Icons.navigate_next),
      ),
    );
  }
}
