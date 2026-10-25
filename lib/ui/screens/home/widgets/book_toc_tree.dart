import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../business_logic/models/book.dart';
import '../../../../business_logic/models/list_item.dart';
import '../../../../business_logic/models/toc.dart';
import '../../../../business_logic/models/toc_list_item.dart';
import '../../../../services/database/database_helper.dart';
import '../../../../services/database/reading_first.dart';
import '../../../../services/provider/script_language_provider.dart';
import '../../../../services/repositories/sentence_toc_repo.dart';
import '../../../../services/repositories/toc_repo.dart';
import '../../../../utils/pali_script.dart';
import '../../../../utils/pali_script_converter.dart';

/// Opens [book] at [page], with [highlight] marked there, or at its first
/// page when [page] is null.
typedef OpenBookAt = void Function(Book book, int? page, String? highlight);

/// Where the reader is: the book in the selected tab and its page. The tree
/// unfolds to it and marks the heading that page falls under.
@immutable
class TreeFocus {
  const TreeFocus(this.bookId, this.page);

  final String bookId;
  final int page;

  @override
  bool operator ==(Object other) =>
      other is TreeFocus && other.bookId == bookId && other.page == page;

  @override
  int get hashCode => Object.hash(bookId, page);
}

/// A book in the library's tree view. Its name opens it, as in the card
/// view; its arrow unfolds its contents, nested by heading level, and a
/// heading opens the book there, as picking it in the contents panel does.
///
/// The contents are read only when first unfolded: a book can have nearly
/// two thousand headings, and the library lists hundreds of books.
class BookTocNode extends StatefulWidget {
  const BookTocNode(
      {super.key, required this.item, required this.open, required this.focus});

  final BookItem item;
  final OpenBookAt open;

  /// Where the reader is. When it is in this book, the book unfolds to the
  /// heading of that page.
  final ValueListenable<TreeFocus?> focus;

  @override
  State<BookTocNode> createState() => _BookTocNodeState();
}

class _BookTocNodeState extends State<BookTocNode> {
  bool _open = false;
  Future<List<_Heading>>? _contents;

  /// The reader's page, while the reader is in this book.
  int? _page;
  final _rowKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.focus.addListener(_onFocus);
    _onFocus();
  }

  @override
  void dispose() {
    widget.focus.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    final f = widget.focus.value;
    final mine = f != null &&
        f.bookId == widget.item.book.id &&
        widget.item.covers(f.page);
    if (!mine) {
      if (_page != null) {
        setState(() {
          _page = null;
          // No book open at all: its contents fold away with the tree.
          if (f == null) _open = false;
        });
      }
      return;
    }
    setState(() {
      _open = true;
      _contents ??= _load();
      _page = f.page;
    });
  }

  Future<List<_Heading>> _load() async {
    final TocRepository repo = DatabaseHelper.sentenceDataAvailable
        ? SentenceTocRepository(DatabaseHelper())
        : TocDatabaseRepository(DatabaseHelper());
    // Ahead of any index being built meanwhile; see ReadingFirst.
    final tocs =
        await ReadingFirst.run(() => repo.getTocs(widget.item.book.id));
    // A book inside a volume shows its own pages' headings only.
    return _Heading.nest(
        tocs.where((t) => widget.item.covers(t.pageNumber)).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Row(
          key: _rowKey,
          open: _open,
          canOpen: true,
          title: widget.item.build(context),
          onToggle: () => setState(() {
            _open = !_open;
            _contents ??= _load();
          }),
          onTap: () =>
              widget.open(widget.item.book, widget.item.fromPage, null),
        ),
        if (_open)
          _Indented(
            child: FutureBuilder<List<_Heading>>(
              future: _contents,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(8),
                    child: LinearProgressIndicator(),
                  );
                }
                final path = _page == null
                    ? const <_Heading>[]
                    : _Heading.pathTo(snapshot.data!, _page!);
                if (_page != null && path.isEmpty) {
                  // Before the first heading: the book itself is the place.
                  _reveal(_rowKey);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final h in snapshot.data!)
                      _HeadingNode(
                          heading: h,
                          book: widget.item.book,
                          open: widget.open,
                          path: path),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

/// A heading and those under it.
class _Heading {
  _Heading(this.toc, this.level);

  final Toc toc;
  final int level;
  final List<_Heading> children = [];

  static int levelOf(String type) => switch (type) {
        'chapter' => 1,
        'title' => 2,
        'subhead' => 3,
        _ => 4,
      };

  /// The heading [page] falls under, the last one starting on or before it,
  /// with the headings above it, outermost first. Empty when the page comes
  /// before the first heading.
  static List<_Heading> pathTo(List<_Heading> roots, int page) {
    var best = <_Heading>[];
    void walk(List<_Heading> nodes, List<_Heading> above) {
      for (final h in nodes) {
        if (h.toc.pageNumber > page) return;
        final here = [...above, h];
        best = here;
        walk(h.children, here);
      }
    }

    walk(roots, const []);
    return best;
  }

  /// The flat contents, in reading order, as a tree: each heading under the
  /// last one of a higher level before it.
  static List<_Heading> nest(List<Toc> tocs) {
    final roots = <_Heading>[];
    final open = <_Heading>[];
    for (final toc in tocs) {
      final h = _Heading(toc, levelOf(toc.type));
      while (open.isNotEmpty && open.last.level >= h.level) {
        open.removeLast();
      }
      (open.isEmpty ? roots : open.last.children).add(h);
      open.add(h);
    }
    return roots;
  }
}

class _HeadingNode extends StatefulWidget {
  const _HeadingNode(
      {required this.heading,
      required this.book,
      required this.open,
      required this.path});

  final _Heading heading;
  final Book book;
  final OpenBookAt open;

  /// The way down to the heading the reader is under; see [_Heading.pathTo].
  final List<_Heading> path;

  @override
  State<_HeadingNode> createState() => _HeadingNodeState();
}

class _HeadingNodeState extends State<_HeadingNode> {
  bool _open = false;
  final _rowKey = GlobalKey();

  bool get _isPlace =>
      widget.path.isNotEmpty && identical(widget.path.last, widget.heading);

  @override
  void initState() {
    super.initState();
    _follow(null);
  }

  @override
  void didUpdateWidget(_HeadingNode old) {
    super.didUpdateWidget(old);
    _follow(old);
  }

  /// Unfolds on the way to the reader's heading, and brings that heading
  /// into view when it has just become the place. Never folds anything:
  /// what the reader opened stays open.
  void _follow(_HeadingNode? old) {
    final onPath = widget.path.any((h) => identical(h, widget.heading));
    if (onPath && !_isPlace) _open = true;
    final wasPlace = old != null &&
        old.path.isNotEmpty &&
        identical(old.path.last, old.heading);
    if (_isPlace && !wasPlace) _reveal(_rowKey);
  }

  TocListItem get _item {
    final toc = widget.heading.toc;
    return switch (toc.type) {
      'chapter' => TocHeadingOne(toc),
      'title' => TocHeadingTwo(toc),
      'subhead' => TocHeadingThree(toc),
      _ => TocHeadingFour(toc),
    };
  }

  /// The heading as it is written in the reader, to mark it there.
  String _highlight(BuildContext context) {
    final name = widget.heading.toc.name.trim();
    final script = context.read<ScriptLanguageProvider>().currentScript;
    return script == Script.roman
        ? name
        : PaliScript.getScriptOf(script: script, romanText: name);
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.heading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Row(
          key: _rowKey,
          open: _open,
          canOpen: h.children.isNotEmpty,
          marked: _isPlace,
          title: _item.build(context, ''),
          onToggle: () => setState(() => _open = !_open),
          onTap: () =>
              widget.open(widget.book, h.toc.pageNumber, _highlight(context)),
        ),
        if (_open)
          _Indented(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in h.children)
                  _HeadingNode(
                      heading: c,
                      book: widget.book,
                      open: widget.open,
                      path: widget.path),
              ],
            ),
          ),
      ],
    );
  }
}

/// One line of the tree: an arrow to unfold, where there is anything under
/// it, and a title that opens.
class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.open,
    required this.canOpen,
    required this.title,
    required this.onToggle,
    required this.onTap,
    this.marked = false,
  });

  final bool open;
  final bool canOpen;

  /// The heading the reader is under, tinted as the contents panel ticks it.
  final bool marked;
  final Widget title;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      // A click leaves no focus behind on the line, which showed as a tint
      // beside the reader's real place in the tree.
      canRequestFocus: false,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 2),
        decoration: marked
            ? BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              )
            : null,
        child: Row(children: [
          SizedBox(
            width: 36,
            height: 32,
            child: canOpen
                ? IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    onPressed: onToggle,
                    icon: AnimatedRotation(
                      turns: open ? 0.25 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: const Icon(Icons.chevron_right),
                    ),
                  )
                : null,
          ),
          Expanded(child: title),
        ]),
      ),
    );
  }
}

/// What lies under a line, set in along a thin guide line.
class _Indented extends StatelessWidget {
  const _Indented({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 17, bottom: 2),
      padding: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: child,
    );
  }
}

/// Scrolls the tree to the row at [key], once it is laid out. The tree is an
/// ordinary list, so Flutter's own ensureVisible measures it rightly.
///
/// Only the tree's own list is scrolled. `Scrollable.ensureVisible` scrolls
/// every scrollable around the row as well, and one of those is the side
/// panel, a page view holding Library, Search, Dictionary, AI and the rest.
/// Run on its own timers (a book's contents loading, a tab change, the
/// reader pausing), it slid that panel part way to another pane, which then
/// showed blank until a rail button snapped it back.
void _reveal(GlobalKey key) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final c = key.currentContext;
    if (c == null || !c.mounted) return;
    final row = c.findRenderObject();
    final list = Scrollable.maybeOf(c);
    if (row == null || list == null) return;
    list.position.ensureVisible(row,
        alignment: 0.3,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic);
  });
}
