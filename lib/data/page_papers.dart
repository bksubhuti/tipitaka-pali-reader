import 'package:flutter/material.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';

/// A paper for the medium page theme: a plain tint, or a texture made for
/// the app (assets/papers, generated from noise, so free of copyright).
class PagePaper {
  const PagePaper({this.color, this.asset, this.edge});

  /// Null for the theme's own tint, the medium page as it always was.
  final Color? color;
  final String? asset;

  /// Darker edges and corners, an image stretched over the whole page:
  /// in the texture they would repeat across it.
  final String? edge;

  String name(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return switch (pagePapers.indexOf(this)) {
      1 => l.paperCream,
      2 => l.paperIvory,
      3 => l.paperSepia,
      4 => l.paperSage,
      5 => l.paperParchment,
      6 => l.paperAgedParchment,
      7 => l.paperRicePaper,
      8 => l.paperPalmLeaf,
      9 => l.paperLinen,
      _ => l.theme,
    };
  }
}

/// Kept in this order: the choice is saved by its place in the list.
const pagePapers = <PagePaper>[
  PagePaper(),
  PagePaper(color: Color(0xFFFAF3E3)),
  PagePaper(color: Color(0xFFFCFAF2)),
  PagePaper(color: Color(0xFFF4E7CC)),
  PagePaper(color: Color(0xFFE7EFE1)),
  // The colours of the textures are their average, for the places that
  // can only take a colour, like the selected tab.
  PagePaper(
      color: Color(0xFFF2E2C8),
      asset: 'assets/papers/parchment.jpg',
      edge: 'assets/papers/parchment_edge.png'),
  PagePaper(
      color: Color(0xFFEDDAB4),
      asset: 'assets/papers/aged_parchment.jpg',
      edge: 'assets/papers/aged_parchment_edge.png'),
  PagePaper(color: Color(0xFFF6F2E7), asset: 'assets/papers/rice_paper.jpg'),
  PagePaper(color: Color(0xFFE7D19A), asset: 'assets/papers/palm_leaf.jpg'),
  PagePaper(color: Color(0xFFF1EBDF), asset: 'assets/papers/linen.jpg'),
];
