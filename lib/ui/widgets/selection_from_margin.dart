import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Lets a selection be begun, or dragged to, in the margin beside the text,
/// taking the line level with the pointer.
///
/// A point beside a block of text is outside it, and a selection there was
/// taken as the block's first or last letter: begun in the margin beside a
/// line, it ran back to the top of the paragraph, every sentence and
/// translation above the line taken with it. Here such a point is moved in
/// to the edge of the text, at the same height, before the block sees it.
class SelectionFromMargin extends StatefulWidget {
  const SelectionFromMargin({super.key, required this.child});

  final Widget child;

  @override
  State<SelectionFromMargin> createState() => _SelectionFromMarginState();
}

class _SelectionFromMarginState extends State<SelectionFromMargin> {
  final _delegate = _MarginDelegate();

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SelectionContainer(delegate: _delegate, child: widget.child);
}

class _MarginDelegate extends StaticSelectionContainerDelegate {
  @override
  SelectionResult handleSelectionEdgeUpdate(SelectionEdgeUpdateEvent event) {
    final text = _textBounds();
    final point = event.globalPosition;
    if (text != null &&
        point.dy >= text.top &&
        point.dy <= text.bottom &&
        (point.dx < text.left || point.dx > text.right)) {
      final inside =
          Offset(point.dx.clamp(text.left + 1, text.right - 1), point.dy);
      event = event.type == SelectionEventType.startEdgeUpdate
          ? SelectionEdgeUpdateEvent.forStart(
              globalPosition: inside, granularity: event.granularity)
          : SelectionEdgeUpdateEvent.forEnd(
              globalPosition: inside, granularity: event.granularity);
    }
    return super.handleSelectionEdgeUpdate(event);
  }

  /// Where the block's text is on the screen.
  Rect? _textBounds() {
    Rect? bounds;
    for (final selectable in selectables) {
      if (selectable.size.isEmpty) continue;
      final box = MatrixUtils.transformRect(
          selectable.getTransformTo(null), Offset.zero & selectable.size);
      bounds = bounds?.expandToInclude(box) ?? box;
    }
    return bounds;
  }
}
