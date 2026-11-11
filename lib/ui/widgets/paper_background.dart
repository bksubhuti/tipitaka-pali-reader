import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
    final edge = Prefs.paper?.edge;
    // The paper and the text each in a layer of their own: scrolling then
    // repaints only the text, and the paper, painted once, is reused. In
    // one layer the full-page texture and edges were painted again on
    // every frame of a scroll.
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: DecoratedBox(
              decoration: Prefs.getPageDecoration(context),
              child: edge == null
                  ? null
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        image: DecorationImage(
                            image: AssetImage(edge), fit: BoxFit.fill),
                      ),
                    ),
            ),
          ),
        ),
        RepaintBoundary(child: child),
      ],
    );
  }
}

/// What the blocks of one scrolling list share to lay their paper: the
/// texture, and where in it each block starts, so that it runs unbroken
/// from block to block.
class PaperFlow {
  ui.Image? _image;
  String? _asset;
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener((info, _) {
    _image = info.image;
    _repaint();
  });
  double _ratio = 1;
  ui.Image? _edge;
  String? _edgeAsset;
  ImageStream? _edgeStream;
  late final ImageStreamListener _edgeListener = ImageStreamListener((info, _) {
    _edge = info.image;
    _repaint();
  });
  final _tops = <int, double>{};
  final _heights = <int, double>{};
  final _strips = <_RenderPaperStrip>{};

  /// The texture's height on the screen, a pixel of it to a pixel.
  double get _tile => _image!.height / _ratio;

  /// The height of one run of the darkened sides, and a multiple of the
  /// texture's so that one number places both.
  double get _edgeRun => _tile * 2;

  void _load(BuildContext context) {
    _ratio = MediaQuery.devicePixelRatioOf(context);
    final paper = Prefs.paper;
    final asset = paper?.asset;
    final edge = asset == null ? null : paper?.edge;
    if (asset == _asset && edge == _edgeAsset) return;
    final configuration = createLocalImageConfiguration(context);
    if (asset != _asset) {
      _asset = asset;
      _stream?.removeListener(_listener);
      _stream = null;
      _image = null;
      if (asset != null) {
        _stream = AssetImage(asset).resolve(configuration)
          ..addListener(_listener);
      }
    }
    if (edge != _edgeAsset) {
      _edgeAsset = edge;
      _edgeStream?.removeListener(_edgeListener);
      _edgeStream = null;
      _edge = null;
      if (edge != null) {
        _edgeStream = AssetImage(edge).resolve(configuration)
          ..addListener(_edgeListener);
      }
    }
    _repaint();
  }

  void _repaint() {
    for (final strip in _strips) {
      strip.markNeedsPaint();
    }
  }

  void _setHeight(int index, double height) {
    final old = _heights[index];
    if (old == height) return;
    _heights[index] = height;
    if (old == null) return;
    // The blocks around it now start elsewhere in the texture: they are
    // placed again from this one.
    _tops.removeWhere((key, _) => key != index);
    _repaint();
  }

  /// How far into the texture the block at [index] starts, so that it
  /// carries on where the block above it ended.
  double _topOf(int index) {
    final known = _tops[index];
    if (known != null) return known;
    var sum = 0.0;
    for (var i = index - 1; i >= 0 && _heights[i] != null; i--) {
      sum += _heights[i]!;
      final top = _tops[i];
      if (top != null) return _tops[index] = (top + sum) % (_edgeRun * 2);
    }
    sum = _heights[index] ?? 0;
    for (var i = index + 1; _heights[i] != null; i++) {
      final top = _tops[i];
      if (top != null) return _tops[index] = (top - sum) % (_edgeRun * 2);
      sum += _heights[i]!;
    }
    // Far from any block placed before, after a jump: a new start.
    if (_tops.isNotEmpty) {
      _tops.clear();
      _repaint();
    }
    return _tops[index] = 0;
  }

  void dispose() {
    _stream?.removeListener(_listener);
    _edgeStream?.removeListener(_edgeListener);
    _strips.clear();
  }
}

/// One block of a scrolling list on its own strip of the paper, which so
/// moves with the text; the strips of a list join into one paper through
/// their [flow]. The paper's darkened sides move with it too. Paints
/// nothing on a page with no texture.
class PaperStrip extends SingleChildRenderObjectWidget {
  const PaperStrip(
      {super.key, required this.flow, required this.index, super.child});

  final PaperFlow flow;
  final int index;

  @override
  RenderObject createRenderObject(BuildContext context) {
    flow._load(context);
    return _RenderPaperStrip(flow, index);
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    flow._load(context);
    (renderObject as _RenderPaperStrip)
      ..flow = flow
      ..index = index;
  }
}

class _RenderPaperStrip extends RenderProxyBox {
  _RenderPaperStrip(this._flow, this._index);

  PaperFlow _flow;
  set flow(PaperFlow value) {
    if (value == _flow) return;
    if (attached) {
      _flow._strips.remove(this);
      value._strips.add(this);
    }
    _flow = value;
    markNeedsPaint();
  }

  int _index;
  set index(int value) {
    if (value == _index) return;
    _index = value;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _flow._strips.add(this);
  }

  @override
  void detach() {
    _flow._strips.remove(this);
    super.detach();
  }

  @override
  void performLayout() {
    super.performLayout();
    _flow._setHeight(_index, size.height);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final image = _flow._image;
    if (image != null) {
      final top = _flow._topOf(_index);
      final canvas = context.canvas;
      canvas.save();
      canvas.clipRect(offset & size);
      final phase = top % _flow._tile;
      paintImage(
        canvas: canvas,
        rect: Rect.fromLTWH(
            offset.dx, offset.dy - phase, size.width, size.height + phase),
        image: image,
        scale: _flow._ratio,
        repeat: ImageRepeat.repeat,
        alignment: Alignment.topLeft,
      );
      final edge = _flow._edge;
      if (edge != null) {
        // The middle of the edge image, where only the sides are dark,
        // one run after another down the paper. Every other run is upside
        // down, so each meets the next without a step.
        final run = _flow._edgeRun;
        final source = Rect.fromLTWH(
            0, edge.height * 0.3, edge.width.toDouble(), edge.height * 0.4);
        final paint = Paint()..filterQuality = FilterQuality.low;
        for (var n = (top / run).floor(); n * run < top + size.height; n++) {
          final y = offset.dy + n * run - top;
          canvas.save();
          if (n.isOdd) {
            canvas.translate(0, 2 * y + run);
            canvas.scale(1, -1);
          }
          canvas.drawImageRect(edge, source,
              Rect.fromLTWH(offset.dx, y, size.width, run), paint);
          canvas.restore();
        }
      }
      canvas.restore();
    }
    super.paint(context, offset);
  }
}
