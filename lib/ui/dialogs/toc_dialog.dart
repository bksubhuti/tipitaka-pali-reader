import 'package:flutter/material.dart';
import 'package:tipitaka_pali/services/repositories/sentence_toc_repo.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:tipitaka_pali/business_logic/models/toc.dart';
import 'package:tipitaka_pali/business_logic/models/toc_list_item.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/ui/dialogs/toc_dialog_view_controller.dart';
import 'package:tipitaka_pali/ui/widgets/pali_search_field.dart';

import '../../services/database/database_helper.dart';
import '../../services/repositories/toc_repo.dart';

class TocDialog extends StatefulWidget {
  final String bookID;
  final int? currentPage;

  const TocDialog({
    super.key,
    required this.bookID,
    this.currentPage,
  });

  @override
  State<TocDialog> createState() => _TocDialogState();
}

class _TocDialogState extends State<TocDialog> {
  int currentIndex = 0;
  AutoScrollController autoScrollController = AutoScrollController();
  late final TocDialogViewController tocDialogViewController;

  @override
  void initState() {
    super.initState();
    tocDialogViewController = TocDialogViewController(
      bookID: widget.bookID,
      tocRepository: DatabaseHelper.sentenceDataAvailable
          ? SentenceTocRepository(DatabaseHelper())
          : TocDatabaseRepository(DatabaseHelper()),
    );

    tocDialogViewController.onLoad();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Column(
        children: [
          Stack(alignment: Alignment.center, children: [
            Text(
              AppLocalizations.of(context)!.table_of_contents,
            ),
            Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context, null),
                  ),
                )),
            Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
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
            ),
          ]),
          const Divider(color: Colors.grey),
          PaliSearchField(
            onTextChanged: (romanText) {
              tocDialogViewController.onFilterChanged(romanText);
            },
            borderRadius: BorderRadius.circular(16),
          ),
          Expanded(
            child: ValueListenableBuilder(
                valueListenable: tocDialogViewController.tocs,
                builder: (_, tocs, __) {
                  if (tocs == null) {
                    return const Center(
                      child: CircularProgressIndicator.adaptive(),
                    );
                  }

                  if (tocs.isEmpty) {
                    return const Center(child: Text('not found'));
                  }
                  currentIndex = getIndex(widget.currentPage, tocs);
                  Future.delayed(const Duration(milliseconds: 500), () {
                    autoScrollController.scrollToIndex(
                      currentIndex,
                      duration: const Duration(milliseconds: 100),
                      preferPosition: AutoScrollPosition.middle,
                    );
                  });

                  return ListView.builder(
                      controller: autoScrollController,
                      itemCount: tocs.length,
                      itemBuilder: (_, index) {
                        final toc = tocs[index];
                        return AutoScrollTag(
                          key: ValueKey(index),
                          controller: autoScrollController,
                          index: index,
                          child: Card(
                            margin: const EdgeInsets.all(1),
                            elevation: .8,
                            child: ListTile(
                              minVerticalPadding: 1,
                              onTap: () => Navigator.pop(context, toc),
                              leading: currentIndex == index
                                  ? const Icon(Icons.check)
                                  : const SizedBox.shrink(),
                              title: getTocListItem(toc).build(
                                  context, tocDialogViewController.filterText),
                              selected: currentIndex == index,
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 1, horizontal: 5),
                            ),
                          ),
                        );
                      });
                }),
          ),
        ],
      ),
    );
  }

  int getIndex(int? currentPage, List<Toc> tocs) {
    if (currentPage == null) return 0;

    // current page contains toc
    for (int i = 0; i < tocs.length; i++) {
      if (tocs[i].pageNumber == currentPage) {
        return i;
      }
    }

    // current page does not contain toc
    for (int i = 0; i < tocs.length; i++) {
      if (tocs[i].pageNumber > currentPage) {
        return i - 1;
      }
    }

    return 0;
  }

  TocListItem getTocListItem(Toc toc) {
    late final TocListItem tocListItem;
    switch (toc.type) {
      case "chapter":
        tocListItem = TocHeadingOne(toc);
        break;
      case "title":
        tocListItem = TocHeadingTwo(toc);
        break;
      case "subhead":
        tocListItem = TocHeadingThree(toc);
        break;
      case "subsubhead":
        tocListItem = TocHeadingFour(toc);
        break;
      default:
        tocListItem = TocHeadingOne(toc);
        break;
    }

    return tocListItem;
  }
}
