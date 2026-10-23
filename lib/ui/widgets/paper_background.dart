import 'package:flutter/material.dart';
import 'package:tipitaka_pali/data/page_papers.dart';
import 'package:tipitaka_pali/services/prefs.dart';

/// The page behind the reader's text: its colour, the paper's texture, and
/// for the papers that have them, edges and corners darkened as on an old
/// sheet.
class PaperBackground extends StatelessWidget {
  const PaperBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final edge = Prefs.selectedPageTheme == PageTheme.medium
        ? pagePapers[Prefs.pagePaper].edge
        : null;
    return Container(
      decoration: Prefs.getPageDecoration(context),
      child: edge == null
          ? child
          : DecoratedBox(
              decoration: BoxDecoration(
                image:
                    DecorationImage(image: AssetImage(edge), fit: BoxFit.fill),
              ),
              child: child,
            ),
    );
  }
}
