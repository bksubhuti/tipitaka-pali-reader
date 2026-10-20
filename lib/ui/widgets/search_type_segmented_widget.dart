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
    _segmentValues[4] = 'AI';
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
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            // A thin line between the choices, so where one ends and the next
            // begins shows without one being selected: "distance any part"
            // read as one run of words.
            child: IntrinsicHeight(
              child: Row(
                children: [
                  for (final (i, entry) in _segmentValues.entries.indexed) ...[
                    if (i > 0)
                      VerticalDivider(
                        width: 9,
                        thickness: 1,
                        indent: 8,
                        endIndent: 8,
                        color: Theme.of(context).dividerColor,
                      ),
                    _segment(context, entry),
                  ]
                ],
              ),
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

  /// One choice. Its label keeps clear of the lines either side, and is
  /// made smaller rather than run into its neighbour when space is short.
  Widget _segment(BuildContext context, MapEntry<int, String> entry) {
    final selected = _selectedIndex == entry.key;
    return Expanded(
      // The icon needs less room than a word, and the words get it.
      flex: entry.key == 4 ? 2 : 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: InkWell(
          borderRadius: BorderRadius.circular(8.0),
          onTap: () {
            if (entry.key == 4) {
              widget.onModeChanged(QueryMode.ai);
              return; // Prevent updating UI selectedIndex for AI
            }

            setState(() {
              _selectedIndex = entry.key;

              isDistanceMoe = _selectedIndex == 2;

              widget.onModeChanged(getQueryModeFromSelection(entry.key));
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4),
            decoration: BoxDecoration(
              color: selected
                  ? Theme.of(context).colorScheme.secondary
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Center(
              // AI as the rail's sparkle, named in its tooltip, so the four
              // ways of matching words have the room.
              child: entry.key == 4
                  ? Tooltip(
                      message: AppLocalizations.of(context)!.aiSearch,
                      child: Icon(Icons.auto_awesome_outlined,
                          size: 20,
                          semanticLabel: AppLocalizations.of(context)!.aiSearch,
                          color: selected
                              ? Colors.white
                              : Theme.of(context).textTheme.bodyLarge?.color),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        entry.value,
                        maxLines: 1,
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : Theme.of(context).textTheme.bodyLarge?.color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
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
