import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';

import '../../../../providers/font_provider.dart';

/// Two fingers spread apart on the text make it larger, and pinched
/// together smaller, as A+ and A− do, and kept the same way.
///
/// The fingers are only watched, not claimed: the text still scrolls and
/// its words are still tapped as before.
class PinchFontSize extends StatefulWidget {
  const PinchFontSize(
      {super.key,
      this.enabled = true,
      this.readSize,
      this.writeSize,
      this.maxSize = 1000,
      required this.child});

  final bool enabled;

  /// The size pinched, and where it goes; the reader's text if not given.
  final int Function(BuildContext context)? readSize;
  final void Function(BuildContext context, int size)? writeSize;
  final int maxSize;
  final Widget child;

  @override
  State<PinchFontSize> createState() => _PinchFontSizeState();
}

class _PinchFontSizeState extends State<PinchFontSize> {
  final _fingers = <int, Offset>{};
  double? _startSpread;
  int _startSize = 0;

  double get _spread {
    final points = _fingers.values.toList();
    return (points[0] - points[1]).distance;
  }

  void _down(PointerDownEvent event) {
    _fingers[event.pointer] = event.position;
    if (_fingers.length == 2) {
      _startSpread = _spread;
      _startSize = _read();
    } else {
      _startSpread = null;
    }
  }

  void _move(PointerMoveEvent event) {
    if (!_fingers.containsKey(event.pointer)) return;
    _fingers[event.pointer] = event.position;
    final start = _startSpread;
    if (start == null || _fingers.length != 2 || start < 1) return;
    _resize(_spread / start);
  }

  int _read() =>
      widget.readSize?.call(context) ??
      context.read<ReaderFontProvider>().fontSize;

  void _resize(double scale) {
    final size = (_startSize * scale).round().clamp(8, widget.maxSize);
    if (size == _read()) return;
    if (widget.writeSize != null) {
      widget.writeSize!(context, size);
    } else {
      context.read<ReaderFontProvider>().setFontSize(size);
    }
  }

  // A trackpad's pinch, on a computer, comes as one pan-zoom gesture.
  void _panZoomStart(PointerPanZoomStartEvent event) => _startSize = _read();

  void _panZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (event.scale != 1.0) _resize(event.scale);
  }

  void _up(PointerEvent event) {
    _fingers.remove(event.pointer);
    _startSpread = null;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      onPointerPanZoomStart: _panZoomStart,
      onPointerPanZoomUpdate: _panZoomUpdate,
      child: widget.child,
    );
  }
}
