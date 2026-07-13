import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../business_logic/models/search_result.dart';
import '../../home/widgets/search_result_list_tile.dart';
import '../controller/search_result_provider.dart';
import 'search_filter_view.dart';
import 'post_search_book_filter_view.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:tipitaka_pali/ui/screens/reader/intents.dart';

class ResultListView extends StatelessWidget implements Escape {
  const ResultListView(
      {super.key,
      required this.searchWord,
      required this.results,
      required this.bookCount});
  final String searchWord;
  final List<SearchResult> results;
  final int bookCount;

  @override
  Widget build(BuildContext context) {
    final notifier = context.read<SearchResultController>();

    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        // push for sumbodhi
        LogicalKeySet(LogicalKeyboardKey.escape): const EscapeIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          EscapeIntent: EscapeAction(this, context),
        },
        child: Scaffold(
          // key: _scaffoldKey,
          appBar: AppBar(
            title: Text('Found ${results.length} in $bookCount books'),
          ),
          body: RawKeyboardListener(
            focusNode: FocusNode(), // Ensure the widget has focus
            onKey: (event) => _handleKeyboardEvent(event, context),
            child: Stack(
              children: [
                results.isEmpty
                    ? const Center(
                        child: Text('Not found'),
                      )
                    : ListView.builder(
                        itemCount: results.length,
                        padding: const EdgeInsets.only(bottom: 70),
                        itemBuilder: (context, index) => SearchResultListTile(
                          result: results[index],
                          onTap: () =>
                              notifier.openBook(results[index], context),
                        ),
                        cacheExtent: 8000,
                      ),
                Positioned(
                    bottom: 16,
                    right: 16,
                    child: Builder(builder: (context) {
                      return Padding(
                        padding: const EdgeInsets.all(45.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            FloatingActionButton.extended(
                              heroTag: "book_filter_btn",
                              onPressed: () => Scaffold.of(context).showBottomSheet(
                                  (context) => const PostSearchBookFilterView()),
                              label: const Text('Book Filter'),
                              icon: const Icon(Icons.book),
                            ),
                            const SizedBox(height: 16),
                            FloatingActionButton.extended(
                              heroTag: "category_filter_btn",
                              onPressed: () => Scaffold.of(context).showBottomSheet(
                                  (context) => const SearchFilterView()),
                              label: Text(AppLocalizations.of(context)!.filter),
                              icon: const Icon(Icons.filter_list),
                            ),
                          ],
                        ),
                      );
                    }))
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleKeyboardEvent(RawKeyEvent event, BuildContext context) {
    // does not seem to work for LogicalKeyboardKey.escape
    if (event is RawKeyUpEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      // it seems as though
      Navigator.of(context).pop(); // Close the view
    }
  }

  @override
  void onEscapeRequested(BuildContext context) {
    debugPrint("escape hit test");
    Navigator.of(context).pop(); // Close the view
  }
}

class ScrollBarThumb extends StatelessWidget {
  final Color backgroundColor;
  final Color drawColor;
  final double height;
  final String title;

  const ScrollBarThumb(
    this.backgroundColor,
    this.drawColor,
    this.height,
    this.title, {
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 64,
          // alignment: Alignment.center,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            // border: Border.all(color: Colors.blue),
            borderRadius: BorderRadius.circular(32),
            color: Theme.of(context).primaryColor,
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimary,
              backgroundColor: Colors.transparent,
              fontSize: 14,
            ),
          ),
        ),
        const Padding(padding: EdgeInsets.all(2)),
        CustomPaint(
          foregroundPainter: _ArrowCustomPainter(drawColor),
          child: Material(
            elevation: 4.0,
            color: backgroundColor,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(height),
              bottomLeft: Radius.circular(height),
              topRight: const Radius.circular(4.0),
              bottomRight: const Radius.circular(4.0),
            ),
            child: Container(
                constraints: BoxConstraints.tight(Size(height * 0.6, height))),
          ),
        ),
      ],
    );
  }
}

class _ArrowCustomPainter extends CustomPainter {
  final Color drawColor;

  _ArrowCustomPainter(this.drawColor);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill
      ..color = drawColor;
    const width = 12.0;
    const height = 8.0;
    final baseX = size.width / 2;
    final baseY = size.height / 2;

    canvas.drawPath(
        trianglePath(Offset(baseX - 4.0, baseY - 2.0), width, height, true),
        paint);
    canvas.drawPath(
        trianglePath(Offset(baseX - 4.0, baseY + 2.0), width, height, false),
        paint);
  }

  static Path trianglePath(
      Offset offset, double width, double height, bool isUp) {
    return Path()
      ..moveTo(offset.dx, offset.dy)
      ..lineTo(offset.dx + width, offset.dy)
      ..lineTo(offset.dx + (width / 2),
          isUp ? offset.dy - height : offset.dy + height)
      ..close();
  }
}
