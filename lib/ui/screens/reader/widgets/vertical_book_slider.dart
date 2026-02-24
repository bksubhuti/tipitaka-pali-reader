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
  late final double min;
  late final double max;
  late final int divisions;
  late int currentPage;

  @override
  void initState() {
    super.initState();
    readerViewController =
        Provider.of<ReaderViewController>(context, listen: false);

    min = readerViewController.book.firstPage.toDouble();
    max = readerViewController.book.lastPage.toDouble();
    divisions = (readerViewController.book.lastPage -
            readerViewController.book.firstPage) +
        1;
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
          value: currentPage.toDouble(),
          min: min,
          max: max,
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
