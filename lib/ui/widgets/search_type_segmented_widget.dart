import 'package:flutter/material.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:tipitaka_pali/ui/screens/home/search_page/easy_number_input.dart';
import '../../../../services/prefs.dart';
import '../screens/home/search_page/search_page.dart';

class SearchTypeSegmentedControl extends StatefulWidget {
  const SearchTypeSegmentedControl(
      {super.key,
      required this.mode,
      required this.wordDistance,
      required this.onModeChanged,
      required this.onDistanceChanged});
  final QueryMode mode;
  final int wordDistance;
  final Function(QueryMode) onModeChanged;
  final Function(int) onDistanceChanged;

  @override
  _SearchTypeSegmentedControlState createState() =>
      _SearchTypeSegmentedControlState();
}

class _SearchTypeSegmentedControlState
    extends State<SearchTypeSegmentedControl> {
  int _selectedIndex = Prefs.queryModeIndex;

  final Map<int, String> _segmentValues = {
    0: 'exact',
    1: 'prefix',
    2: 'distance',
    3: 'any part',
    4: 'AI ✨',
  };

  late bool isDistanceMoe;

  @override
  void initState() {
    super.initState();
    isDistanceMoe = _selectedIndex == 2;
  }

  void addLocalizedSegmentValues(BuildContext context) {
    _segmentValues[0] = AppLocalizations.of(context)!.exact;
    _segmentValues[1] = AppLocalizations.of(context)!.prefix;
    _segmentValues[2] = AppLocalizations.of(context)!.distance;
    _segmentValues[3] = AppLocalizations.of(context)!.anyPart;
    _segmentValues[4] = 'AI ✨';
  }

  @override
  Widget build(BuildContext context) {
    //set localized values for buttons
    addLocalizedSegmentValues(context);

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).dividerColor,
              width: 1.0,
            ),
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _segmentValues.entries.map((entry) {
                return Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedIndex = entry.key;

                        isDistanceMoe = _selectedIndex == 2;

                        widget.onModeChanged(
                            getQueryModeFromSelection(entry.key));
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      decoration: BoxDecoration(
                        color: _selectedIndex == entry.key
                            ? Theme.of(context).colorScheme.secondary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: Center(
                        child: Text(
                          entry.value,
                          style: TextStyle(
                            color: _selectedIndex == entry.key
                                ? Colors.white
                                : Theme.of(context).textTheme.bodyLarge?.color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        // extra setting for distance
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) {
            return SizeTransition(
              sizeFactor: animation,
              axis: Axis.vertical,
              child: child,
            );
          },
          child: isDistanceMoe
              ? Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Text(AppLocalizations.of(context)!.distanceBetweenWords),
                      const Spacer(),
                      EasyNumberInput(
                          initial: widget.wordDistance,
                          onChanged: (value) {
                            widget.onDistanceChanged(value);
                          }),
                      // right margin
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  QueryMode getQueryModeFromSelection(int key) {
    QueryMode qm = QueryMode.exact;
    switch (key) {
      case 1:
        qm = QueryMode.prefix;
        break;
      case 2:
        qm = QueryMode.distance;
        break;
      case 3:
        qm = QueryMode.anywhere;
        break;
      case 4:
        qm = QueryMode.ai;
        break;
    }

    return qm;
  }
}
