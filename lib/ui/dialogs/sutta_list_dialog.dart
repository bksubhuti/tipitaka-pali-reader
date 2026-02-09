import 'package:el_tooltip/el_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:substring_highlight/substring_highlight.dart';
import 'package:tipitaka_pali/utils/platform_info.dart';
import '../../business_logic/models/sutta.dart';
import '../../services/prefs.dart';
import '../../services/provider/script_language_provider.dart';
import '../../services/repositories/sutta_repository.dart';
import '../../utils/pali_script.dart';
import '../../utils/pali_script_converter.dart';
import 'sutta_list_dialog_view_controller.dart';
import '../screens/home/widgets/search_bar.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
//import 'package:flutter/src/material/search_anchor.dart';

class SuttaListDialog extends StatefulWidget {
  const SuttaListDialog({
    super.key,
    required this.suttaRepository,
  });

  final SuttaRepository suttaRepository;

  @override
  State<SuttaListDialog> createState() => _SuttaListDialogState();
}

class _SuttaListDialogState extends State<SuttaListDialog> {
  late final TextEditingController textEditingController;
  late final SuttaListDialogViewController viewController;

  final ScrollController scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    textEditingController = TextEditingController();
    viewController = SuttaListDialogViewController(widget.suttaRepository);
    viewController.onLoad();
  }

  @override
  void dispose() {
    textEditingController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedScript = context.read<ScriptLanguageProvider>().currentScript;
    return Column(
      children: [
        SizedBox(
          height: 50,
          child: Stack(alignment: Alignment.center, children: [
            Text(
              AppLocalizations.of(context)!.searchSuttaName,
              style:
                  const TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: ElTooltip(
                content: Text(AppLocalizations.of(context)!.qjHelpMessage),
                child: const Icon(Icons.question_mark),
              ),
            ),
            const Align(
              alignment: Alignment.centerRight,
              child: CloseButton(),
            )
          ]),
        ),
        const Divider(color: Colors.grey),
        PlatformInfo.isDesktop ? _getTprSearchBar() : const SizedBox.shrink(),
        Expanded(
          child: ValueListenableBuilder<Iterable<Sutta>?>(
              valueListenable: viewController.suttas,
              builder: (_, suttas, __) {
                if (suttas == null || suttas.isEmpty) {
                  return Center(
                    child: Text(AppLocalizations.of(context)!.notFound),
                  );
                }

                return ScrollConfiguration(
                  behavior: const ScrollBehavior().copyWith(
                    scrollbars: false,
                  ),
                  child: Scrollbar(
                    controller: scrollController,
                    child: ListView.separated(
                      controller: scrollController,
                      itemCount: suttas.length,
                      itemBuilder: (context, index) {
                        final sutta = suttas.elementAt(index);

                        // Original (Roman) title used for matching/highlighting
                        final rawTitle = sutta.shortcut.isNotEmpty
                            ? '[${sutta.shortcut}] ${sutta.name}'
                            : sutta.name;

                        // Translated display title (could be Sinhala, Burmese, etc.)
                        final displayTitle = getDisplayText(
                            text: rawTitle, script: selectedScript);

                        // Ensure the search filter term matches the displayed script
                        final displayFilter = getDisplayText(
                            text: viewController.filter,
                            script: selectedScript);

                        final displaySubtitle = getDisplayText(
                          text: '${sutta.bookName} • ${sutta.pageNumber}',
                          script: selectedScript,
                        );

                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          elevation: 0.5,
                          child: ListTile(
                            minVerticalPadding: 6,
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 4, horizontal: 10),
                            onTap: () {
                              Navigator.pop(context, sutta);
                            },
                            title: SubstringHighlight(
                              text: displayTitle,
                              term: displayFilter, // <-- crucial fix here
                              textStyle:
                                  Theme.of(context).textTheme.titleMedium!,
                              textStyleHighlight: Theme.of(context)
                                  .textTheme
                                  .titleMedium!
                                  .copyWith(
                                    color: Theme.of(context).primaryColor,
                                    //fontWeight: FontWeight.bold,
                                  ),
                            ),
                            subtitle: Text(
                              displaySubtitle,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    color: Theme.of(context).hintColor,
                                  ),
                            ),
                          ),
                        );
                      },
                      separatorBuilder: (context, index) {
                        return const Divider(
                          height: 1,
                          indent: 16.0,
                          endIndent: 16.0,
                        );
                      },
                    ),
                  ),
                );
              }),
        ),
        !PlatformInfo.isDesktop ? _getTprSearchBar() : const SizedBox.shrink(),
      ],
    );
  }

  String getDisplayText({required String text, required Script script}) {
    if (script == Script.roman) {
      return text;
    }
    return PaliScript.getScriptOf(
      romanText: text,
      script: script,
    );
  }

  Widget _getTprSearchBar() {
    return Row(
      children: [
        Expanded(
          child: TprSearchBar(
            hint: AppLocalizations.of(context)!.nameOrShorthand,
            controller: textEditingController,
            onTextChanged: viewController.onFilterChanged,
            onSubmitted: (value) {
              if (viewController.suttas.value != null) {
                if (viewController.suttas.value!.isNotEmpty) {
                  Navigator.pop(context, viewController.suttas.value!.first);
                }
              }
            },
          ),
        ),
        FilterChip(
            label: Text(
              AppLocalizations.of(context)!.fuzzy,
              style: const TextStyle(fontSize: 12),
            ),
            selected: Prefs.isFuzzy,
            onSelected: (value) {
              setState(() {
                Prefs.isFuzzy = !Prefs.isFuzzy;
              });
            }),
      ],
    );
  }
/*
  _showQjHelpDialog(context) async {
    return (await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            //title: Text(AppLocalizations.of(context)!.help),
            content: Text(AppLocalizations.of(context)!.qjHelpMessage),
            actions: <Widget>[
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(false), //<-- SEE HERE
                child: Text(AppLocalizations.of(context)!.close),
              ),
            ],
          ),
        )) ??
        false;
  }*/
}

class CloseButton extends StatelessWidget {
  final EdgeInsets? padding;
  const CloseButton({super.key, this.padding});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.only(right: 16.0),
      child: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.pop(context, null),
      ),
    );
  }
}
