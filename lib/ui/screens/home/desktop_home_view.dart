import 'package:flutter/material.dart';
import 'package:tipitaka_pali/data/constants.dart';
import 'package:tipitaka_pali/providers/navigation_provider.dart';

import '../../widgets/my_vertical_divider.dart';
import '../reader/reader_container.dart';
import 'dekstop_navigation_bar.dart';
import 'navigation_pane.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/services/prefs.dart';

class DesktopHomeView extends StatefulWidget {
  const DesktopHomeView({Key? key}) : super(key: key);

  @override
  State<DesktopHomeView> createState() => _DesktopHomeViewState();
}

class _DesktopHomeViewState extends State<DesktopHomeView>
    with SingleTickerProviderStateMixin {
  final _width = 350.0;

  late final AnimationController _animationController;
  late final Tween<double> _tween;
  late final Animation<double> _animation;

  late final NavigationProvider navigationProvider;

  @override
  void initState() {
    super.initState();
    navigationProvider = context.read<NavigationProvider>();

    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: Prefs.animationSpeed.round()),
    );

    _tween = Tween(begin: 1.0, end: 0.0);
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.fastOutSlowIn,
    );

    navigationProvider.addListener(_openCloseChangedListener);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _openCloseChangedListener() {
    final isOpened = navigationProvider.isNavigationPaneOpened;
    if (isOpened) {
      _animationController.reverse();
    } else {
      _animationController.forward();
      // _animatedIconController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Row(
          children: [
            const DeskTopNavigationBar(),
            const MyVerticalDivider(width: 2),
            // Naviagation Pane
            SizeTransition(
              sizeFactor: _tween.animate(_animation),
              axis: Axis.horizontal,
              axisAlignment: 1,
              child: SizedBox(
                width: _width,
                child: const DetailNavigationPane(navigationCount: 6),
              ),
            ),
            // reader view
            const Expanded(child: ReaderContainer()),
          ],
        ),
        Align(
          alignment: Alignment.bottomLeft,
          child: SizedBox(
            width: navigationBarWidth,
            height: 64,
            child: Center(
              child: IconButton(
                  onPressed: () =>
                      context.read<NavigationProvider>().toggleNavigationPane(),
                  icon: AnimatedIcon(
                    icon: AnimatedIcons.arrow_menu,
                    // progress: _animatedIconController,
                    progress: _animationController.view,
                  )),
            ),
          ),
        )
      ],
    );
  }
}
