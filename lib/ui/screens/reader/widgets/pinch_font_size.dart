import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../providers/font_provider.dart';

/// Two fingers spread apart on the text make it larger, and pinched
/// together smaller, as A+ and A− do, and kept the same way.
///
/// The fingers are only watched, not claimed: the text still scrolls and
/// its words are still tapped as before.
class PinchFontSize extends StatefulWidget {
  const PinchFontSize({super.key, this.enabled = true, required this.child});

  final bool enabled;
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
      _startSize = context.read<ReaderFontProvider>().fontSize;
    } else {
      _startSpread = null;
    }
  }

  void _move(PointerMoveEvent event) {
    if (!_fingers.containsKey(event.pointer)) return;
    _fingers[event.pointer] = event.position;
    final start = _startSpread;
    if (start == null || _fingers.length != 2 || start < 1) return;
    final size = max(8, (_startSize * _spread / start).round());
    context.read<ReaderFontProvider>().setFontSize(size);
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
      child: widget.child,
    );
  }
}
