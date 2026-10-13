import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/ui/screens/reader/controller/reader_view_controller.dart';

class VerticalBookSlider extends StatefulWidget {
  const VerticalBookSlider({super.key});

  @override
  State<VerticalBookSlider> createState() => _BookSliderState();
}

class _BookSliderState extends State<VerticalBookSlider> {
  late final ReaderViewController readerViewController;
  late final int min;
  late final int max;
  late final int divisions;
  late int currentPage;

  @override
  void initState() {
    super.initState();
    readerViewController =
        Provider.of<ReaderViewController>(context, listen: false);

    min = readerViewController.book.firstPage;
    // A one-page book would give the slider no range at all.
    max = readerViewController.book.lastPage > min
        ? readerViewController.book.lastPage
        : min + 1;
    divisions = max - min;
    currentPage = readerViewController.currentPage.value;
    readerViewController.currentPage.addListener(_listenPageChange);
  }

  @override
  void dispose() {
    readerViewController.currentPage.removeListener(_listenPageChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotatedBox(
      quarterTurns: 1,
      child: SliderTheme(
        data: SliderThemeData(
          trackHeight: 16,
          trackShape: const _EvenTrackShape(),
          activeTrackColor: Colors.grey[100],
          inactiveTrackColor: Colors.grey[100],
          thumbShape: const RoundSliderThumbShape(
            enabledThumbRadius: 8,
            disabledThumbRadius: 8,
            pressedElevation: 0,
          ),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 8.0),
        ),
        child: Slider(
          // Kept inside the range: a page outside it, such as an old bookmark
          // on a page the book no longer has, made the slider fail to draw.
          value: currentPage.clamp(min, max).toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          label: currentPage.toString(),
          divisions: divisions,
          onChanged: (value) async {
            // setState(() {
            //   currentPage = value.toInt();
            // });
            await readerViewController.onGoto(
                pageNumber: value.toInt(), saveToRecent: false);
          },
          // onChangeStart: null,
          onChangeEnd: (value) {
            readerViewController.onGoto(pageNumber: value.toInt());
          },
        ),
      ),
    );
  }

  void _listenPageChange() {
    if (mounted) {
      setState(() {
        currentPage = readerViewController.currentPage.value;
      });
    }
  }
}

/// The slider's track, as thick before the thumb as after it. Flutter's own
/// draws the part before the thumb 2 px thicker, which on this scrollbar,
/// turned on its side, made it wider above the thumb than below.
class _EvenTrackShape extends RoundedRectSliderTrackShape {
  const _EvenTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    super.paint(context, offset,
        parentBox: parentBox,
        sliderTheme: sliderTheme,
        enableAnimation: enableAnimation,
        textDirection: textDirection,
        thumbCenter: thumbCenter,
        secondaryOffset: secondaryOffset,
        isDiscrete: isDiscrete,
        isEnabled: isEnabled,
        additionalActiveTrackHeight: 0);
  }
}
