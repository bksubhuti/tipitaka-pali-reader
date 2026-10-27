import 'dart:io';

import 'package:flutter/material.dart';

class PlatformInfo {
  static final bool _isDesktop =
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  static bool get isDesktop => _isDesktop;
  static bool get isMobile => Platform.isAndroid || Platform.isIOS;
}

// In flutter, there are roughly 96 logical pixels per inch or 38 per cm.
// A device whose shorter side is 600 or more is a tablet (an 8 inch iPad
// mini is 744 wide); the shorter side stays the same as it is turned.
class Mobile {
  static bool _isTabletDevice(BuildContext context) =>
      MediaQuery.of(context).size.shortestSide >= 600;

  /// Laid out as on a computer, with the side panel and the reader beside
  /// it: only a tablet held sideways.
  static bool isTablet(BuildContext context) =>
      !PlatformInfo.isDesktop &&
      _isTabletDevice(context) &&
      MediaQuery.of(context).orientation == Orientation.landscape;

  /// The phone layout, with the tabs and the ☰ panel: a phone either way up,
  /// and a tablet held upright.
  static bool isPhone(BuildContext context) =>
      !PlatformInfo.isDesktop && !isTablet(context);
}
