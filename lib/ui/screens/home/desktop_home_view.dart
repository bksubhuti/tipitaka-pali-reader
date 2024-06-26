import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:tipitaka_pali/data/constants.dart';
import 'package:tipitaka_pali/providers/navigation_provider.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/rx_prefs.dart';

import '../../../data/flex_theme_data.dart';
import '../../widgets/my_vertical_divider.dart';
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
  // late  double width;

  late final AnimationController _animationController;
  late final Tween<double> _tween;
  late final Animation<double> _animation;

  late final NavigationProvider navigationProvider;

  @override
  void initState() {
    super.initState();
    // width = Prefs.panelSize.toDouble();
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
    // RydMike: Avoid things like this, prefer using themes correctly!
    //   But OK sometimes needed, but rarely. Not sure why this is used in
    //   conditional build below. Looks like some temp experiment. :)
    final isOrange2 = Prefs.themeName == MyThemes.orange2Name;
    return PreferenceBuilder<double>(
        preference: context
            .read<StreamingSharedPreferences>()
            .getDouble(panelSizeKey, defaultValue: defaultPanelSize),
        builder: (context, width) {
          return Stack(
            children: [
              Row(
                children: [
                  if (isOrange2)
                    Container(
                      decoration: const BoxDecoration(
                          border:
                              Border(right: BorderSide(color: Colors.grey))),
                      child: const DeskTopNavigationBar(),
                    ),
                  if (!isOrange2) ...[
                    const DeskTopNavigationBar(),
                    const MyVerticalDivider(width: 2),
                  ],
                  // Navigation Pane
                  SizeTransition(
                    sizeFactor: _tween.animate(_animation),
                    axis: Axis.horizontal,
                    axisAlignment: 1,
                    child: SizedBox(
                      width: width,
                      child: const DetailNavigationPane(navigationCount: 7),
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
                        onPressed: () => context
                            .read<NavigationProvider>()
                            .toggleNavigationPane(),
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
        });
  }
}
