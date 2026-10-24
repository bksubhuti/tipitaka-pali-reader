import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../business_logic/models/book.dart';
import '../../../../services/prefs.dart';
import '../../../../services/provider/script_language_provider.dart';
import '../../../../utils/font_utils.dart';
import '../../../../utils/pali_script.dart';
import 'home_shortcuts.dart';

/// One passage for the home screen, with the place in the texts it comes
/// from.
class Quote {
  final int day;
  final String pali;
  final String label;
  final String? bookId;
  final String? bookName;
  final int? page;
  final String? highlight;

  const Quote({
    required this.day,
    required this.pali,
    required this.label,
    this.bookId,
    this.bookName,
    this.page,
    this.highlight,
  });

  factory Quote.fromJson(Map<String, dynamic> json) => Quote(
        day: json['day'] as int,
        pali: json['pali'] as String,
        label: json['label'] as String? ?? '',
        bookId: json['book_id'] as String?,
        bookName: json['book_name'] as String?,
        page: json['page'] as int?,
        highlight: json['highlight'] as String?,
      );
}

/// The lists the home screen's quote can come from, chosen in settings.
enum QuoteList {
  /// Basic verses and lists to know by heart, from the refuges, then in a
  /// mixed order: the file keeps them grouped, for editing.
  versesToKnow('verses', 'assets/data/verses_to_know.json', shuffled: true),

  /// DPR's Daily Buddha Vacana (CC BY-NC-SA 4.0): one for each day of the
  /// year, so the first time starts on today's.
  dailyBuddhaVacana('dbv', 'assets/data/quotes.json', startOnDayOfYear: true);

  final String id;
  final String asset;
  final bool startOnDayOfYear;
  final bool shuffled;
  const QuoteList(this.id, this.asset,
      {this.startOnDayOfYear = false, this.shuffled = false});

  static QuoteList fromId(String id) =>
      values.firstWhere((l) => l.id == id, orElse: () => versesToKnow);
}

/// The list chosen in settings; the card follows it when it changes.
final quoteList = ValueNotifier<QuoteList>(QuoteList.fromId(Prefs.quoteList));

final Map<QuoteList, Future<List<Quote>>> _loaded = {};

/// A list's quotes, read once from its asset, in the order they are shown.
Future<List<Quote>> _quotes(QuoteList list) =>
    _loaded[list] ??= rootBundle.loadString(list.asset).then((s) {
      final quotes = [
        for (final q in (jsonDecode(s)['quotes'] as List))
          if (q['pali'] != null) Quote.fromJson(q as Map<String, dynamic>)
      ];
      if (list.shuffled && quotes.length > 1) {
        // The first stays first; the rest mixed, the same way every time, so
        // each day moves on to the next and none comes again until all
        // have. The place is kept by day number, so editing the file loses
        // no one's.
        final rest = quotes.sublist(1)..shuffle(Random(108));
        return [quotes.first, ...rest];
      }
      return quotes;
    });

/// The quote to show today. The reader keeps their place in each list: each
/// new day moves on one quote from where they were.
int quoteIndexForToday(QuoteList list, List<Quote> quotes) {
  final now = DateTime.now();
  final today = '${now.year}-${now.month}-${now.day}';
  final saved = Prefs.quoteDay(list.id);
  var index = saved == null
      ? (list.startOnDayOfYear
          ? now.difference(DateTime(now.year, 1, 1)).inDays
          : 0)
      : quotes.indexWhere((q) => q.day == saved);
  if (index < 0) index = 0;
  if (saved != null && Prefs.quoteDate(list.id) != today) index++;
  index %= quotes.length;
  Prefs.setQuoteDay(list.id, quotes[index].day);
  Prefs.setQuoteDate(list.id, today);
  return index;
}

/// The home screen's card: the day's Pāḷi, and under it where it is from. A
/// tap opens the book on that page; the refresh button moves on to another,
/// and the card stays there.
class QuoteOfDayCard extends StatefulWidget {
  const QuoteOfDayCard({super.key});

  @override
  State<QuoteOfDayCard> createState() => _QuoteOfDayCardState();
}

class _QuoteOfDayCardState extends State<QuoteOfDayCard> {
  QuoteList? _list;
  int? _index;

  void _next(List<Quote> quotes) {
    setState(() {
      _index = (_index! + 1) % quotes.length;
      Prefs.setQuoteDay(_list!.id, quotes[_index!].day);
    });
  }

  @override
  Widget build(BuildContext context) {
    final script = context.watch<ScriptLanguageProvider>().currentScript;
    final fontName = FontUtils.getfontName(script: script);
    final colors = Theme.of(context).colorScheme;

    return ValueListenableBuilder<QuoteList>(
      valueListenable: quoteList,
      builder: (context, list, _) => FutureBuilder<List<Quote>>(
        future: _quotes(list),
        builder: (context, snapshot) {
          final quotes = snapshot.data ?? const <Quote>[];
          if (quotes.isEmpty) return const SizedBox.shrink();
          if (_list != list) {
            _list = list;
            _index = quoteIndexForToday(list, quotes);
          }
          final quote = quotes[_index!];
          // Verses read best large; a prose passage needs room.
          final isShort = quote.pali.length < 200;
          return ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: quote.bookId == null || quote.page == null
                          ? null
                          : () => openBookAt(
                              context,
                              Book(
                                  id: quote.bookId!,
                                  name: quote.bookName ?? ''),
                              quote.page!,
                              highlight: quote.highlight),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 18, 8, 18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              PaliScript.getScriptOf(
                                  script: script, romanText: quote.pali),
                              textAlign: TextAlign.center,
                              // A long passage is cut short here; the tap opens
                              // the whole of it.
                              maxLines: 14,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: isShort ? 22 : 17,
                                fontFamily: fontName,
                                color: colors.onSurface,
                                fontWeight:
                                    isShort ? FontWeight.bold : FontWeight.w500,
                                height: 1.4,
                              ),
                            ),
                            if (quote.label.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  PaliScript.getScriptOf(
                                      script: script, romanText: quote.label),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontFamily: fontName,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // The next in the list's order: for the verses, a mixed one,
                  // so another at random, and none again until all have been.
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    color: colors.onSurfaceVariant,
                    onPressed: () => _next(quotes),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
