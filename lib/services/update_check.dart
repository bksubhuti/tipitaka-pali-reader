import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'prefs.dart';

/// Whether a newer build of TPR is out for this platform, as messages.json
/// in the repository says.
///
/// The file is read at most once a day. The button shows only when this
/// build is two or more behind: a store can take days to pass a build, and
/// one build behind is not worth a reader's notice. So the release step is
/// to raise the platform's `currentVersion` in messages.json once the store
/// has the build.
class UpdateCheck {
  UpdateCheck._();

  static const _source =
      'https://cdn.jsdelivr.net/gh/bksubhuti/tipitaka-pali-reader@master/messages.json';

  /// How many builds behind before the button shows.
  static const behind = 2;

  /// The store page to update from, once an update is due; null until then.
  static final ValueNotifier<Uri?> storePage = ValueNotifier(null);

  static bool _started = false;

  /// Checks once per start of the app.
  static Future<void> start() async {
    if (_started) return;
    _started = true;
    final page = _storePage();
    final own = _buildOf(Prefs.versionNumber);
    if (page == null || own == null) return;
    final today = _day(DateTime.now());
    if (Prefs.updateCheckedOn != today) {
      try {
        final response = await http
            .get(Uri.parse(_source))
            .timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final latest = _buildOf('${data[_platform]?['currentVersion']}');
          if (latest != null) Prefs.latestBuild = latest;
          Prefs.updateCheckedOn = today;
        }
      } catch (e) {
        // Offline, or the file is unreadable: asked again at the next start.
        debugPrint('update check failed: $e');
      }
    }
    if (Prefs.latestBuild - own >= behind &&
        Prefs.latestBuild > Prefs.updateDismissedBuild) {
      storePage.value = page;
    }
  }

  /// Puts the button away until a build newer than the latest is out.
  static void dismiss() {
    Prefs.updateDismissedBuild = Prefs.latestBuild;
    storePage.value = null;
  }

  static String get _platform => Platform.operatingSystem;

  static Uri? _storePage() => switch (_platform) {
        'android' => Uri.parse(
            'https://play.google.com/store/apps/details?id=com.paauk.tipitakapalireader'),
        'ios' => Uri.parse('https://apps.apple.com/app/id1541426949'),
        'macos' => Uri.parse('macappstore://apps.apple.com/app/id1541426949'),
        'windows' =>
          Uri.parse('ms-windows-store://pdp/?productid=9MTH9TD82TGR'),
        'linux' => Uri.parse(
            'https://flathub.org/apps/org.americanmonk.TipitakaPaliReader'),
        _ => null,
      };

  /// The build number of a version such as 3.1.4+135, or of 135 alone.
  static int? _buildOf(String version) =>
      int.tryParse(version.split('+').last.trim());

  static String _day(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
}
