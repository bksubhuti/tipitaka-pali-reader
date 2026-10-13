/// Picks where a multi-word search lands on a page.
///
/// Prefix and distance searches highlight each word wherever it occurs, so a
/// page holds stray single words as well as the place that actually matched.
/// Landing on the first highlight stopped short at a lone "dhammā" above the
/// real "kusalā dhammā pacchimānaṃ". This finds the first highlight that
/// starts a group holding every search word, close enough together to have
/// matched.
class SearchCluster {
  SearchCluster._();

  static final _tag = RegExp(r'<[^>]*>');
  static final _space = RegExp(r'\s+');

  /// [html] with [id] put on the first highlight (`<span class="[cssClass]">`)
  /// of the first group that holds all of [words] as prefixes, with at most
  /// [maxGap] other words between the first and the last. Without such a
  /// group, the first highlight gets it.
  static String markStart(String html, String cssClass, List<String> words,
      int maxGap, String id) {
    final open = '<span class="$cssClass">';
    final spans = RegExp('${RegExp.escape(open)}(.*?)</span>', dotAll: true)
        .allMatches(html)
        .toList();
    if (spans.isEmpty) return html;

    final wanted = [for (final w in words) w.toLowerCase()];
    final joined = wanted.join();

    // Each highlight's word position on the page, and the search words it
    // stands for. A compound written as one word stands for all of them.
    final positions = <int>[];
    final covers = <Set<int>>[];
    var position = 0;
    var at = 0;
    var afterSpace = true;
    for (final span in spans) {
      final before = html.substring(at, span.start).replaceAll(_tag, '');
      if (before.isNotEmpty) {
        final trimmed = afterSpace ? before.trimLeft() : before;
        position += _space.allMatches(trimmed).length;
        afterSpace = before.endsWith(' ') || before.endsWith('\n');
      }
      positions.add(position);
      final text = span.group(1)!.replaceAll(_tag, '').toLowerCase();
      covers.add({
        for (var i = 0; i < wanted.length; i++)
          if (text.startsWith(wanted[i]) ||
              (wanted.length > 1 && text.startsWith(joined)))
            i,
      });
      at = span.end;
      afterSpace = false;
    }

    final start = _firstGroup(positions, covers, wanted.length, maxGap);

    final target = spans[start < 0 ? 0 : start];
    return html.replaceRange(target.start, target.start + open.length,
        '<span id="$id" class="$cssClass">');
  }

  /// Whether the text of [html] holds all of [words] as prefixes of words
  /// with at most [maxGap] other words between the first and the last.
  static bool hasGroup(String html, List<String> words, int maxGap) {
    final wanted = [for (final w in words) w.toLowerCase()];
    if (wanted.isEmpty) return false;
    final joined = wanted.join();
    final tokens = html
        .replaceAll(_tag, ' ')
        .split(_space)
        .where((t) => t.isNotEmpty)
        .toList();
    final positions = <int>[];
    final covers = <Set<int>>[];
    for (var p = 0; p < tokens.length; p++) {
      final token = tokens[p].replaceAll(_leading, '').toLowerCase();
      final cover = {
        for (var i = 0; i < wanted.length; i++)
          if (token.startsWith(wanted[i]) ||
              (wanted.length > 1 && token.startsWith(joined)))
            i,
      };
      if (cover.isEmpty) continue;
      positions.add(p);
      covers.add(cover);
    }
    return _firstGroup(positions, covers, wanted.length, maxGap) >= 0;
  }

  static final _leading = RegExp(r'''^[\s"'“”‘’(\[\-–—]+''');

  /// The first of the matches, at word [positions] standing for search words
  /// [covers], that starts a group holding all [count] of them within
  /// [maxGap] words of each other; -1 when there is none.
  static int _firstGroup(
      List<int> positions, List<Set<int>> covers, int count, int maxGap) {
    final reach = maxGap + count - 1;
    for (var i = 0; i < positions.length; i++) {
      if (covers[i].isEmpty) continue;
      final found = <int>{};
      for (var j = i; j < positions.length; j++) {
        if (positions[j] - positions[i] > reach) break;
        found.addAll(covers[j]);
        if (found.length == count) return i;
      }
    }
    return -1;
  }
}
