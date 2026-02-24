import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/ui/screens/reader/controller/reader_view_controller.dart';

class BookSlider extends StatefulWidget {
  const BookSlider({super.key});

  @override
  State<BookSlider> createState() => _BookSliderState();
}

class _BookSliderState extends State<BookSlider> {
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
    return Slider(
      value: currentPage.toDouble(),
      min: min,
      max: max,
      label: currentPage.toString(),
      divisions: divisions,
      onChanged: (value) {
        if (mounted) {
          setState(() {
            currentPage = value.toInt();
          });
        }
      },
      // onChangeStart: null,
      onChangeEnd: (value) {
        readerViewController.onGoto(pageNumber: value.toInt());
      },
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
