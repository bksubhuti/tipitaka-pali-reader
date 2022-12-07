import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../business_logic/models/search_result.dart';
import '../../home/widgets/search_result_list_tile.dart';
import '../controller/search_result_provider.dart';
import 'search_filter_view.dart';

class ResultListView extends StatelessWidget {
  const ResultListView(
      {Key? key,
      required this.searchWord,
      required this.results,
      required this.bookCount})
      : super(key: key);
  final String searchWord;
  final List<SearchResult> results;
  final int bookCount;

  @override
  Widget build(BuildContext context) {
    final notifier = context.read<SearchResultController>();

    return Scaffold(
      // key: _scaffoldKey,
      appBar: AppBar(
        title: Text('Found ${results.length} in $bookCount books'),
      ),
      body: Stack(
        children: [
          results.isEmpty
              ? const Center(
                  child: Text('Not found'),
                )
              : ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, index) => SearchResultListTile(
                    result: results[index],
                    onTap: () => notifier.openBook(results[index], context),
                  ),
                ),
          Positioned(
              bottom: 16,
              right: 16,
              child: Builder(builder: (context) {
                return FloatingActionButton.extended(
                  onPressed: () => Scaffold.of(context)
                      .showBottomSheet((context) => const SearchFilterView()),
                  label: const Text('Filter'),
                  icon: const Icon(Icons.filter_list),
                );
              }))
        ],
      ),
    );
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
    Key? key,
  }) : super(key: key);

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
