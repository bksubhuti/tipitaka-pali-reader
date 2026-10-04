/// Builds a reader page out of ePitaka sentences.
///
/// TPR's reader consumes one HTML string per page and does everything else on
/// top of that string: script conversion, word tap lookup, highlighting, the
/// search anchor and TTS. So moving to sentence-based data does not mean
/// rewriting the reader. It means producing the same HTML from sentences
/// instead of reading it out of the `pages` table, which is what this does.
///
/// The markup deliberately matches what the existing pages contain, because
/// the reader already knows how to treat it:
///
///   * `<p class="bodytext">` opens an ordinary paragraph, and
///     `noindentbodytext` one that continues across the page break;
///   * `<a name="para5">` marks a paragraph for navigation. The number itself
///     is not written out: ePitaka's text already begins with it;
///   * `<a name="P1.0023"></a>` placed at a word is turned into a visible
///     `[P 1.23]` badge by the reader, under the user's own preference;
///   * `<span class="note">` wraps a variant reading, which the reader already
///     hides when the user turns alternate readings off;
///   * `<span class="palitext">` and `<span class="translation_text">` mark
///     the halves of a bilingual page, which the reader already styles and
///     can hide independently. Only written when a translation is present.
///     Each translation carries its language, `lang="en"`;
///   * `<a name="s12_3"></a>` marks where sentence 3 of paragraph 12 begins.
///     Reading aloud follows these to highlight the sentence being spoken
///     and to start at the one the reader tapped. Being an empty anchor, it
///     passes through script conversion and the find-in-book pattern, which
///     already steps over anchors between words; the reader removes it
///     before display.
///
/// Nothing here touches Flutter or the database, so it can be tested on its
/// own, which matters: a page that composes wrongly is hard to spot by eye and
/// easy to check by machine.
library;

/// Where a printed edition's page begins, inside one sentence.
class PageAnchor {
  /// `M`, `V`, `P` or `T`: Myanmar, VRI, PTS, Thai.
  final String edition;
  final int volume;
  final int page;

  /// Word offset inside the sentence. 0 means the page begins at the
  /// sentence's first word.
  final int wordIndex;

  const PageAnchor({
    required this.edition,
    required this.volume,
    required this.page,
    required this.wordIndex,
  });

  /// The anchor spelling the reader already recognises, e.g. `V1.0023`.
  String get name =>
      '$edition$volume.${page.toString().padLeft(4, '0')}';
}

/// How a sentence joins what comes before it.
enum GlueState {
  /// Opens a new paragraph.
  paragraph,

  /// Continues the previous paragraph; no new paragraph is opened.
  continues,

  /// A line of verse, which breaks but is not a prose paragraph.
  verse,
}

/// One ePitaka sentence, with what the reader needs to place it.
class PageSentence {
  final int paraId;
  final int lineId;
  final String pali;

  /// Paragraph number shown at the head of a paragraph, when there is one.
  final String? paraNum;

  final GlueState glue;

  /// The heading level when this sentence is a heading: 1 to 7 from
  /// ePitaka's headings, 1 the largest, or 0 for a title line at the head of
  /// a book. Null for ordinary text.
  final int? headingLevel;

  /// Page beginnings that fall inside this sentence, in word order.
  final List<PageAnchor> anchors;

  /// Translations of this sentence, in the order the reader wants them shown.
  /// Empty for a Pali-only page, which is then written without the bilingual
  /// wrapper so it looks exactly as it does today.
  final List<String> translations;

  const PageSentence({
    required this.paraId,
    required this.lineId,
    required this.pali,
    this.paraNum,
    this.glue = GlueState.paragraph,
    this.headingLevel,
    this.anchors = const [],
    this.translations = const [],
  });
}

class PageComposer {
  PageComposer._();

  static const _classFor = {
    GlueState.paragraph: 'bodytext',
    GlueState.continues: 'noindentbodytext',
    GlueState.verse: 'gatha1',
  };

  /// Composes the page HTML for [sentences], in reading order.
  ///
  /// [continuesFromPreviousPage] opens the first paragraph as a continuation,
  /// which is what a page beginning mid-sentence needs.
  ///
  /// [languages] names the language of each translation, in the same order
  /// as [PageSentence.translations].
  ///
  /// [withCredit] opens the page with [translationCredit], as its own block.
  static String compose(
    List<PageSentence> sentences, {
    bool continuesFromPreviousPage = false,
    List<String> languages = const [],
    bool withCredit = false,
  }) {
    if (sentences.isEmpty) return '';

    final buffer = StringBuffer();
    if (withCredit) buffer.write(translationCredit);
    int? openParaId;
    var first = true;
    var previousHadTranslation = false;

    for (final sentence in sentences) {
      final startsParagraph = sentence.paraId != openParaId;

      if (startsParagraph) {
        if (openParaId != null) buffer.write('</p>');
        var glue = sentence.glue;
        if (first && continuesFromPreviousPage && glue == GlueState.paragraph) {
          glue = GlueState.continues;
        }
        final heading = sentence.headingLevel;
        buffer
          ..write('<p class="')
          ..write(heading != null
              ? headingClass(heading)
              : _classFor[glue] ?? 'bodytext')
          ..write('">');
        if (sentence.paraNum != null && sentence.paraNum!.isNotEmpty) {
          // Anchor only, no visible number. ePitaka's own text already opens
          // the paragraph with it, so writing it again shows it twice. The
          // anchor is what paragraph navigation jumps to, and the reader
          // strips it before display.
          buffer.write('<a name="para${sentence.paraNum}"></a>');
        }
        openParaId = sentence.paraId;
      } else if (previousHadTranslation) {
        // The sentence before ended with its translation, so this one's Pali
        // must start on its own line. Joined with a space instead, the Pali
        // runs on from the English and the two languages become one muddled
        // paragraph.
        buffer.write('<br>');
      } else {
        buffer.write(' ');
      }

      buffer
        ..write('<a name="${sentenceMarker(sentence.paraId, sentence.lineId)}">'
            '</a>')
        ..write(_sentenceHtml(sentence, languages));
      previousHadTranslation =
          sentence.translations.any((t) => t.isNotEmpty);
      first = false;
    }

    if (openParaId != null) buffer.write('</p>');
    return markVariantReadings(buffer.toString());
  }

  /// A variant reading in ePitaka is written `[anubaddhā (ka. sī. pī.)]`: the
  /// alternative, then the editions it comes from in brackets. TPR's own pages
  /// wrap exactly that in `<span class="note">`, and the reader strips those
  /// when the user has alternate readings turned off.
  ///
  /// ePitaka carries the same text without the span, so it is added here and
  /// the existing preference works untouched. Only bracketed groups closing
  /// with a parenthesised source are wrapped. Other brackets in the text are
  /// cross-references and editorial remarks, not variants, and hiding those
  /// would take away content the reader never asked to lose.
  static final _variantReading =
      RegExp(r'\[[^\[\]]*\([^()]*\)\s*\]');

  /// The credit and caution for the ePitaka translations, written at the top
  /// of a book's first page when a translation is shown.
  ///
  /// The text sits in a `translation_text` span so that it is treated as a
  /// translation is: not turned into the reader's Pali script, and hidden
  /// with the translations when the reader shows Pali only. It carries no
  /// sentence marker, so reading aloud passes over it.
  static const translationCredit = '<p class="centered">'
      '<span class="translation_text"><i>'
      'Epitaka.org AI Translation (2026) — use with discretion.<br>'
      'The translation was created with Myanmar Nissaya data provided by '
      'Wikipali.org.'
      '</i></span></p>';

  /// The class a heading of [level] is written with, `heading1` to
  /// `heading7`, or `heading0` for a title line. The reader sizes them.
  static String headingClass(int level) => 'heading${level.clamp(0, 7)}';

  /// The name of the anchor marking where a sentence begins.
  static String sentenceMarker(int paraId, int lineId) => 's${paraId}_$lineId';

  /// Matches every sentence marker, for removing them before display.
  static final sentenceMarkers = RegExp(r'<a name="s\d+_\d+"></a>');

  static String markVariantReadings(String html) => html.replaceAllMapped(
      _variantReading, (m) => '<span class="note">${m.group(0)}</span>');

  /// How many `<p>` blocks [compose] would write for these sentences.
  ///
  /// Counted rather than composed, so the reader can size its list without
  /// building every page of the book first. It mirrors the one condition
  /// [compose] uses to open a paragraph, so the two cannot drift apart
  /// without this line changing too.
  static int blockCount(List<PageSentence> sentences,
      {bool withCredit = false}) {
    if (sentences.isEmpty) return 0;
    var blocks = withCredit ? 1 : 0;
    int? openParaId;
    for (final sentence in sentences) {
      if (sentence.paraId != openParaId) {
        blocks++;
        openParaId = sentence.paraId;
      }
    }
    return blocks;
  }

  /// The paragraph blocks of a composed page, in order.
  ///
  /// The reader's list scrolls by block rather than by page, so it needs the
  /// page cut back into the pieces this class wrote. Running an HTML parser
  /// over the output to recover them costs more than composing it did, and it
  /// is unnecessary: every block is a `<p ...>` opened and closed by
  /// [compose], with no nested paragraph, so they can be read straight off
  /// the string.
  static List<String> blocksOf(String html) {
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

  /// One sentence, with its translations beneath it when there are any.
  ///
  /// A sentence with no translation is written plainly, exactly as a Pali-only
  /// page always has been. Only when a translation is present does the Pali
  /// get wrapped in `palitext`, because that wrapper is how the reader knows
  /// a page is bilingual and which half to hide when the user asks for one
  /// language or the other.
  ///
  /// Order is the caller's: Pali first, then each translation in the order the
  /// reader has chosen in settings.
  static String _sentenceHtml(PageSentence sentence, List<String> languages) {
    final pali = _withAnchors(sentence);
    if (sentence.translations.isEmpty) return pali;

    final buffer = StringBuffer()
      ..write('<span class="palitext">')
      ..write(pali)
      ..write('</span>');
    for (var i = 0; i < sentence.translations.length; i++) {
      final translation = sentence.translations[i];
      if (translation.isEmpty) continue;
      buffer.write('<br><span class="translation_text"');
      if (i < languages.length) buffer.write(' lang="${languages[i]}"');
      buffer
        ..write('>')
        ..write(translation)
        ..write('</span>');
    }
    return buffer.toString();
  }

  /// Puts each anchor at its word, leaving the words themselves untouched.
  static String _withAnchors(PageSentence sentence) {
    if (sentence.anchors.isEmpty) return sentence.pali;

    final words = sentence.pali.split(' ');
    final byIndex = <int, List<PageAnchor>>{};
    for (final anchor in sentence.anchors) {
      final at = anchor.wordIndex.clamp(0, words.length);
      byIndex.putIfAbsent(at, () => []).add(anchor);
    }

    final buffer = StringBuffer();
    for (var i = 0; i <= words.length; i++) {
      for (final anchor in byIndex[i] ?? const <PageAnchor>[]) {
        buffer.write('<a name="${anchor.name}"></a>');
      }
      if (i < words.length) {
        if (i > 0) buffer.write(' ');
        buffer.write(words[i]);
      }
    }
    return buffer.toString();
  }
}
