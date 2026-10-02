import 'dart:convert';

import 'package:tipitaka_pali/utils/page_composer.dart';

List<PageContent> pageContentFromJson(String str) => List<PageContent>.from(
    json.decode(str).map((x) => PageContent.fromJson(x)));

String pageContentToJson(List<PageContent> data) =>
    json.encode(List<dynamic>.from(data.map((x) => x.toJson())));

class PageContent {
  int? id;
  String? bookID;
  int? pageNumber;
  String? paragraphNumber;

  /// Builds the page when it is first wanted.
  ///
  /// Opening a book used to compose every one of its pages before showing
  /// any: 117 ms for the largest, on a desktop. The list shows one page at a
  /// time, so the rest is work done in front of the reader for nothing. A
  /// page built this way composes when it is first looked at and remembers
  /// the result.
  String Function()? _build;
  String? _content;

  /// How many paragraph blocks this page holds, when that is known without
  /// building it. The reader's list needs the count up front even though it
  /// only draws the blocks on screen.
  final int? blockCount;

  /// The sentences the page was composed from, when it came from the
  /// sentence data, and the language of each of their translations. Reading
  /// aloud speaks from these rather than from the HTML.
  final List<PageSentence>? sentences;
  final List<String> languages;

  PageContent(
      {this.id = 0,
      this.bookID = "",
      this.pageNumber = 0,
      String content = "",
      this.paragraphNumber = "",
      String Function()? build,
      this.blockCount,
      this.sentences,
      this.languages = const []})
      : _content = build == null ? content : null,
        _build = build;

  String get content {
    final build = _build;
    if (build != null) {
      _content = build();
      _build = null;
    }
    return _content ?? '';
  }

  /// The page cut into the blocks the reader's list scrolls through.
  List<String> get blocks => _blocks ??= _blocksOf(content);
  List<String>? _blocks;

  /// Reads the `<p>` blocks straight off the string. They are written by the
  /// page composer, never nested, so a parser is not needed to find them —
  /// and running one costs more than composing the page did.
  static List<String> _blocksOf(String html) {
    final blocks = <String>[];
    var at = 0;
    while (true) {
      final open = html.indexOf('<p ', at);
      if (open < 0) break;
      final close = html.indexOf('</p>', open);
      if (close < 0) break;
      blocks.add(html.substring(open, close + 4));
      at = close + 4;
    }
    return blocks;
  }

  factory PageContent.fromJson(Map<dynamic, dynamic> json) {
    return PageContent(
      id: json["id"] ?? 0,
      bookID: json["bookid"] ?? "n/a",
      pageNumber: json["page"] ?? "n/a",
      content: json["content"] ?? "n/a",
      paragraphNumber: json["paranum"] ?? "n/a",
    );
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "bookid": bookID,
        "page": pageNumber,
        "content": content,
        "paranum": paragraphNumber
      };

  @override
  String toString() {
    return '$id: $content';
  }
}
