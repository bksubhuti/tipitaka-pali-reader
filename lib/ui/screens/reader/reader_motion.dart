import 'package:flutter/widgets.dart';
import 'package:tipitaka_pali/services/prefs.dart';

/// How the reader moves when it is sent somewhere: a search result, the
/// contents, go to page or paragraph, find in book.
///
/// The text runs to the place, as the contents list runs to the current
/// heading, so the reader sees which way it went and where it landed. It
/// takes the animation speed set in Settings; at 0, or on a device set to
/// reduce motion, it jumps as it always did.
class ReaderMotion {
  ReaderMotion._();

  static const curve = Curves.easeInOutCubic;

  /// Where a place lands, as a fraction of the screen from the top: a
  /// heading or word a fifth of the way down, clear of the toolbar, with
  /// the text after it filling the rest.
  static const landAt = 0.2;

  /// The animation speed from Settings.
  static Duration get duration =>
      Duration(milliseconds: Prefs.animationSpeed.round());

  /// Whether to move here rather than jump.
  static bool glides(BuildContext context) =>
      duration > Duration.zero &&
      !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  /// [duration], or none where motion is turned off.
  static Duration of(BuildContext context) =>
      glides(context) ? duration : Duration.zero;
}
