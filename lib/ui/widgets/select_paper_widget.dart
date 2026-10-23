import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/data/page_papers.dart';
import 'package:tipitaka_pali/services/provider/theme_change_notifier.dart';
import 'package:tipitaka_pali/ui/widgets/colored_text.dart';

/// The paper of the medium page: its name and a swatch, and a menu of the
/// papers to choose from.
class SelectPaperWidget extends StatelessWidget {
  const SelectPaperWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<ThemeChangeNotifier>();
    final current = pagePapers[notifier.pagePaper];

    // The name and the swatch open the menu too, not just the arrow.
    return PopupMenuButton<int>(
      padding: EdgeInsets.zero,
      // Over the whole window, so a click anywhere outside the menu, on the
      // reader too, closes it; narrow, so it still fits the Settings panel.
      useRootNavigator: true,
      constraints: const BoxConstraints(maxWidth: 200),
      // Just under its row, not over it: over it, a long list is pushed up
      // to the top of the window, away from the row.
      position: PopupMenuPosition.under,
      // No initialValue: the menu would scroll to it, and the scroll can
      // move the side panels' PageView, showing the next panel.
      onSelected: notifier.onChangePagePaper,
      itemBuilder: (context) => <PopupMenuItem<int>>[
        for (int i = 0; i < pagePapers.length; i++)
          PopupMenuItem<int>(
            value: i,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            // A plain row, narrower than a ListTile, so the menu stays
            // inside the Settings panel.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Swatch(paper: pagePapers[i], size: 28),
                const SizedBox(width: 10),
                Flexible(child: ColoredText(pagePapers[i].name(context))),
              ],
            ),
          )
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ColoredText(current.name(context)),
          const SizedBox(width: 8),
          _Swatch(paper: current, size: 26),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.paper, required this.size});

  final PagePaper paper;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = paper.asset;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // The theme's own tint, for the paper that has no colour of its own.
        color: paper.color ?? Theme.of(context).colorScheme.surfaceContainer,
        image: asset == null
            ? null
            : DecorationImage(image: AssetImage(asset), fit: BoxFit.cover),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
    );
  }
}
