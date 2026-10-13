import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/data/constants.dart';
import 'package:tipitaka_pali/providers/navigation_provider.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import '../reader/reader_container.dart';
import 'dekstop_navigation_bar.dart';
import 'navigation_pane.dart';

class DesktopHomeView extends StatefulWidget {
  const DesktopHomeView({super.key});

  @override
  State<DesktopHomeView> createState() => _DesktopHomeViewState();
}

class _DesktopHomeViewState extends State<DesktopHomeView>
    with SingleTickerProviderStateMixin {
  late double panelWidth;

  late final AnimationController _animationController;
  late final Tween<double> _tween;
  late final Animation<double> _animation;

  late final NavigationProvider navigationProvider;

  @override
  void initState() {
    super.initState();
    // width = Prefs.panelSize.toDouble();
    panelWidth = Prefs.panelWidth;
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
    debugPrint('isOpened: $isOpened');
    debugPrint('is animation complete: ${_animationController.isCompleted}');
    debugPrint('animation value: ${_animationController.value}');
    debugPrint('tween value: ${_tween.evaluate(_animation)}');
    if (isOpened) {
      _animationController.reverse();
    } else {
      _animationController.forward();
      // _animatedIconController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    // RydMike: Avoid things like this, prefer using themes correctly!
    //   But OK sometimes needed, but rarely. Not sure why this is used in
    //   conditional build below. Looks like some temp experiment. :)
    return Stack(
      children: [
        Row(
          children: [
            // Navigation Rail
            Container(
              decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: Colors.grey))),
              child: const DeskTopNavigationBar(),
            ),
            // Navigation Pane
            SizeTransition(
              sizeFactor: _tween.animate(_animation),
              axis: Axis.horizontal,
              axisAlignment: 1,
              child: SizedBox(
                width: panelWidth,
                child: const DetailNavigationPane(navigationCount: 7),
              ),
            ),
// drag bar
            MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                onHorizontalDragUpdate: (DragUpdateDetails details) {
                  setState(() {
                    final screenWidth = MediaQuery.of(context)
                        .size
                        .width; // Get the current window width
                    final maxWidth = screenWidth -
                        300; // Assuming you want to leave at least 300px for the rest of the content
                    const minWidth = 250.0;

                    panelWidth += details.primaryDelta ?? 0;
                    panelWidth = panelWidth.clamp(
                        minWidth, maxWidth); // Apply dynamic constraints
                    Prefs.panelWidth =
                        panelWidth; // Optionally save the new width to preferences
                  });
                },
                child: const _ResizeHandle(),
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

/// The bar between the side panel and the reader, dragged to resize them:
/// a thin line with a grip of three dots at its middle, as in VS Code.
///
/// The line is in the middle of the bar. It used to sit at the bar's right
/// edge, which left a blank strip on the panel's side and made every page
/// in the panel look wider on the right than on the left.
class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle();

  @override
  Widget build(BuildContext context) {
    final line = Theme.of(context).dividerColor;
    return Container(
      // Wide enough to take hold of, with the same space either side.
      width: 11,
      color: Colors.transparent,
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(width: 1, color: line),
          Container(
            width: 7,
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(color: line),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 3,
                    height: 3,
                    margin: const EdgeInsets.symmetric(vertical: 1.5),
                    decoration: const BoxDecoration(
                        color: Colors.grey, shape: BoxShape.circle),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
