import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Keeps a child of a lazily built list alive while [selecting] is true.
///
/// A list child scrolled out of view is let go, and a selection in it goes
/// with it. Text selected across many children, by dragging past the edge of
/// the list so that it scrolls, kept only the first and the last.
///
/// The list must keep children alive on request (`addAutomaticKeepAlives`).
class KeepWhileSelecting extends StatefulWidget {
  const KeepWhileSelecting(
      {super.key, required this.selecting, required this.child});

  final ValueListenable<bool> selecting;
  final Widget child;

  @override
  State<KeepWhileSelecting> createState() => KeepWhileSelectingState();
}

class KeepWhileSelectingState extends State<KeepWhileSelecting>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.selecting.value;

  @override
  void initState() {
    super.initState();
    widget.selecting.addListener(updateKeepAlive);
  }

  @override
  void dispose() {
    widget.selecting.removeListener(updateKeepAlive);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
