import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:substring_highlight/substring_highlight.dart';
import '../../business_logic/models/sutta.dart';
import '../../services/provider/script_language_provider.dart';
import '../../services/repositories/sutta_repository.dart';
import '../../utils/pali_script.dart';
import '../../utils/pali_script_converter.dart';
import 'sutta_list_dialog_view_controller.dart';
import '../screens/home/widgets/search_bar.dart';
import '../../utils/mm_number.dart';

class SuttaListDialog extends StatefulWidget {
  const SuttaListDialog({
    Key? key,
    required this.suttaRepository,
  }) : super(key: key);

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
          child: Stack(alignment: Alignment.center, children: const [
            Text(
              'suttas',
              style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: CloseButton(),
            )
          ]),
        ),
        const Divider(color: Colors.grey),
        Expanded(
          child: ValueListenableBuilder<Iterable<Sutta>?>(
              valueListenable: viewController.suttas,
              builder: (_, suttas, __) {
                if (suttas == null) {
                  return const Center(
                      child: CircularProgressIndicator.adaptive());
                }

                if (suttas.isEmpty) {
                  return const Center(
                    child: Text('not found'),
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
                        return ListTile(
                          onTap: () => Navigator.pop(context, sutta),
                          title: SubstringHighlight(
                            term: getDisplayText(
                              text: viewController.filter,
                              script: selectedScript,
                            ),
                            textStyleHighlight:
                                const TextStyle(color: Colors.red),
                            text: getDisplayText(
                                text: sutta.name, script: selectedScript),
                            textStyle: TextStyle(
                              fontSize: 18.0,
                              color: Theme.of(context).colorScheme.onBackground,
                            ),
                          ),
                          subtitle: Text(getDisplayText(
                            text: '${sutta.bookName} - ${sutta.pageNumber}',
                            script: selectedScript,
                          )),
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
        SearchBar(
          hint: 'search by sutta',
          controller: textEditingController,
          onTextChanged: viewController.onFilterChanged,
          onSubmitted: (value) {
            // not use
          },
        ),
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
}

class CloseButton extends StatelessWidget {
  final EdgeInsets? padding;
  const CloseButton({Key? key, this.padding}) : super(key: key);

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