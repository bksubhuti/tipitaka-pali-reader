import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/providers/navigation_provider.dart';
import 'package:tipitaka_pali/utils/platform_info.dart';

/// Puts the cursor in a pane's text box each time the pane is chosen on the
/// navigation rail, so the word can be typed straight away.
///
/// Only when chosen there: moving to the dictionary because a word was
/// tapped leaves the focus in the reader, where its keys still work.
///
/// Desktop only. On a phone or tablet taking the focus brings up the
/// on-screen keyboard over the pane, which is not wanted every time it is
/// opened; there is no reliable way to tell whether a device would show one.
class FocusWhenShown extends StatefulWidget {
  const FocusWhenShown({
    super.key,
    required this.navigationIndex,
    required this.focusNode,
    required this.child,
  });

  /// The pane's place on the navigation rail.
  final int navigationIndex;
  final FocusNode focusNode;
  final Widget child;

  @override
  State<FocusWhenShown> createState() => _FocusWhenShownState();
}

class _FocusWhenShownState extends State<FocusWhenShown> {
  NavigationProvider? _navigation;

  /// The rail choices already answered. Starting from none, a pane built
  /// because it was just chosen takes the focus as it opens.
  int _answered = 0;

  @override
  void initState() {
    super.initState();
    if (!PlatformInfo.isDesktop) return;
    _navigation = context.read<NavigationProvider>();
    _navigation!.addListener(_onNavigation);
    _onNavigation();
  }

  @override
  void dispose() {
    _navigation?.removeListener(_onNavigation);
    super.dispose();
  }

  void _onNavigation() {
    final navigation = _navigation!;
    if (navigation.railChoices == _answered) return;
    _answered = navigation.railChoices;
    if (!navigation.isNavigationPaneOpened ||
        navigation.lastRailChoice != widget.navigationIndex) {
      return;
    }
    // After the pane has been switched to, and only while nothing, such as
    // a page of search results, is open over it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent == false) return;
      widget.focusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
