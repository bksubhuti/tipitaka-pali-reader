"""
Shared text handling for the TPR to ePitaka migration.

One tokenizer is used everywhere, so that a word offset means the same thing in
every step. Getting this wrong silently shifts page markers, so the rules are
spelled out rather than left to a regular expression read in passing.

Rules:

  * HTML tags become whitespace.
  * Text is normalized to NFC first, so that a Pali letter written as a base
    plus a combining mark compares equal to its composed form.
  * A token is a run of Pali letters or digits. Every other character, including
    quotation marks, the peyyala ellipsis, dashes and punctuation, separates.
  * Case is folded.

Diacritics are significant and are preserved exactly; only case is folded.

Note on quotation marks. The two sources place them differently around the
elided "iti": TPR writes atthasamhita'nti, ePitaka writes atthasamhitan ' ti.
Splitting on the quotation mark leaves both as two tokens in the same place, so
the streams stay the same length and a position still means the same word. The
two tokens differ in where the nasal sits, which alignment reports as a local
replacement of equal size, and offsets carry through it unchanged.
"""

import re
import unicodedata

TAG_RE = re.compile(r"<[^>]*>")

# Pali in roman script, including the diacritics TPR and ePitaka use.
PALI_LETTERS = "a-zāīūṭḍṇṅñṃḷṛ"
SPLIT_RE = re.compile("[^0-9%s]+" % PALI_LETTERS)


def strip_tags(text):
    return TAG_RE.sub(" ", text)


def tokenize(text, strip_html=True):
    """Return the normalized word list for a piece of Pali text."""
    if strip_html:
        text = strip_tags(text)
    text = unicodedata.normalize("NFC", text).lower()
    return [w for w in SPLIT_RE.split(text) if w]


def tpr_word_stream(cur, book_id):
    """Concatenate one TPR book's pages into a single word list.

    Pages are joined in page order. TPR pages do not repeat a catchword at the
    boundary, so joining them introduces no duplicate words.
    """
    words = []
    for (html,) in cur.execute(
            "SELECT content FROM pages WHERE bookid=? ORDER BY page", (book_id,)):
        if html:
            words.extend(tokenize(html))
    return words


def epitaka_word_stream(cur, book_id):
    """Concatenate one ePitaka book's sentences into a single word list.

    Returns (words, spans) where spans[i] is (para_id, line_id, offset) for
    word i: the sentence that word belongs to and its offset within that
    sentence. That is what turns an aligned position into a row plus a word
    offset.
    """
    words = []
    spans = []
    for para_id, line_id, pali in cur.execute(
            "SELECT para_id, line_id, pali FROM sentences WHERE book_id=? "
            "ORDER BY para_id, line_id", (book_id,)):
        if not pali:
            continue
        toks = tokenize(pali, strip_html=False)
        for offset, w in enumerate(toks):
            words.append(w)
            spans.append((para_id, line_id, offset))
    return words, spans
