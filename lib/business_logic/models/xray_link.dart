/// One commentary link out of a sentence: the word or phrase the commentary
/// takes up, and the commentary sentence that explains it. From ePitaka's
/// `book_links`.
class XrayLink {
  final String word;
  final String book;
  final int para;
  final int line;

  const XrayLink({
    required this.word,
    required this.book,
    required this.para,
    required this.line,
  });
}

/// The links of every sentence composed so far, by a small number.
///
/// A page carries `<xray data-x="17"></xray>` rather than the links
/// themselves. The reader matches tapped words and highlights against the raw
/// page HTML, and Pāḷi words written into an attribute would be found there
/// too. A number is never taken for a word.
class XrayIndex {
  XrayIndex._();

  static final _links = <List<XrayLink>>[];
  static final _ids = <String, int>{};

  /// The number for the links of the sentence named by [key], the same each
  /// time the sentence is composed.
  static int idFor(String key, List<XrayLink> links) =>
      _ids.putIfAbsent(key, () {
        _links.add(links);
        return _links.length - 1;
      });

  static List<XrayLink>? linksOf(int id) =>
      id >= 0 && id < _links.length ? _links[id] : null;
}
