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

    final first = readerViewController.book.firstPage;
    // A one-page book would give the slider no range at all.
    final last = readerViewController.book.lastPage > first
        ? readerViewController.book.lastPage
        : first + 1;
    min = first.toDouble();
    max = last.toDouble();
    divisions = last - first;
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
      // Kept inside the range: a page outside it, such as an old bookmark on
      // a page the book no longer has, made the slider fail to draw.
      value: currentPage.toDouble().clamp(min, max),
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
