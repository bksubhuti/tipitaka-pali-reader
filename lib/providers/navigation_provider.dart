import 'package:flutter/material.dart';

// final currentNavigation = ValueNotifier(0);
// final isNavigationViewOpened = ValueNotifier(true);

class NavigationProvider extends ChangeNotifier {
  int currentNavigation = 0;
  bool isNavigationPaneOpened = true;

  /// Set while a translation is being installed, updated or removed from
  /// the settings pane. The pane keeps no page it is moved away from, and
  /// moving it off the install part way through, as a word tapped in the
  /// reader did to show the dictionary, crashed the app. So the pane stays
  /// where it is until the work ends; a tapped word opens the dictionary in
  /// its side sheet instead.
  static final paneLocked = ValueNotifier<bool>(false);

  // Todo - fix hardcoding
  final int _indexOfSearchNavigation = 3;
  final int _indexOfDictionaryNavigation = 4;
  final int _indexOfSettingNavigation = 5;
  // Desktop and tablet only, drawn on the rail just below Search. Given the
  // next free number rather than slotted in after Search, so the phone's
  // bottom bar, which has no AI tab, keeps its numbering.
  final int _indexOfAiSearchNavigation = 6;
  int get indexOfAiSearchNavigation => _indexOfAiSearchNavigation;
  int get indexOfSettingNavigation => _indexOfSettingNavigation;
  int get indexOfSearchNavigation => _indexOfSearchNavigation;
  int get indexOfDictionaryNavigation => _indexOfDictionaryNavigation;

  /// Counts the times a pane has been chosen on the navigation rail, and
  /// which was chosen last. Moving to the dictionary because a word was
  /// tapped in the reader is not counted.
  int railChoices = 0;
  int lastRailChoice = 0;

  void onClickedNavigationItem(int index) {
    if (paneLocked.value) return;
    railChoices++;
    lastRailChoice = index;
    if (!isNavigationPaneOpened) {
      isNavigationPaneOpened = !isNavigationPaneOpened;
      currentNavigation = index;
    } else if (currentNavigation == index) {
      isNavigationPaneOpened = !isNavigationPaneOpened;
    } else {
      currentNavigation = index;
    }
    notifyListeners();
  }

  void toggleNavigationPane() {
    if (paneLocked.value) return;
    isNavigationPaneOpened = !isNavigationPaneOpened;
    notifyListeners();
  }

  void moveToDictionaryPage() {
    if (paneLocked.value) return;
    currentNavigation = _indexOfDictionaryNavigation;
    notifyListeners();
  }

  void moveToSearchPage() {
    if (paneLocked.value) return;
    currentNavigation = _indexOfSearchNavigation;
    notifyListeners();
  }

  /// The library, as from the phone's Open Book button.
  void moveToBookList() {
    if (paneLocked.value) return;
    currentNavigation = 0;
    notifyListeners();
  }

  void moveToSettingPage() {
    currentNavigation = _indexOfSettingNavigation;
    notifyListeners();
  }
}
