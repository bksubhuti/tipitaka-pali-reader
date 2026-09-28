#!/usr/bin/env python3
"""
Extract page-marker positions and paragraph structure from the original TPR
database (tipitaka_pali.db).

The original pages carry inline anchors marking where each printed edition's
page begins, at the exact word:

    ... buddhassa<a name="M1.0002"></a> avannam ...

means Myanmar volume 1 page 2 begins at the word after "buddhassa".

Editions: M = Myanmar, V = VRI, P = PTS, T = Thai.

For every anchor this records the word offset within the book's continuous word
stream, plus a short context fingerprint on each side. Paragraph structure is
recorded in the same pass, so a sentence can later be marked "keep with next"
where the original had no paragraph break.

Word offsets are counted with the shared tokenizer in pali_text, the same one
the matching step uses on both databases. That has to hold: an offset counted
one way and looked up another silently moves every page marker, which is the
error this whole exercise exists to avoid. Anchors are carried through
tokenization as sentinel tokens spelled with q and x, letters romanized Pali
does not use, so they survive as ordinary words and can be counted in place.

The source database is opened read-only. Outputs original_markers.db and a
per-book report.
"""

import argparse
import os
import re
import sqlite3
import sys

from pali_text import tokenize

ANCHOR_RE = re.compile(r'<a\s+name="([MVPT])(\d+)\.(\d+)"[^>]*>\s*</a\s*>', re.I)
P_OPEN_RE = re.compile(r'<p\b[^>]*>', re.I)
P_CLASS_RE = re.compile(r'<p\b[^>]*class="([^"]*)"[^>]*>', re.I)
TAG_RE = re.compile(r"<[^>]*>")

MARK_SENTINEL = " qxqm%dqxq "
PARA_SENTINEL = " qxqp%dqxq "
SENTINEL_RE = re.compile(r"^qxq([mp])(\d+)qxq$")

EDITIONS = {"M": "myanmar", "V": "vri", "P": "pts", "T": "thai"}
CONTEXT_WORDS = 6


def mark_page(html, marks, paras):
    """Replace anchors and paragraph opens with sentinels, then strip tags."""

    def _anchor(m):
        marks.append((m.group(1).upper(), int(m.group(2)), int(m.group(3))))
        return MARK_SENTINEL % (len(marks) - 1)

    def _para(m):
        cls = P_CLASS_RE.search(m.group(0))
        paras.append(cls.group(1) if cls else "")
        return PARA_SENTINEL % (len(paras) - 1)

    text = ANCHOR_RE.sub(_anchor, html)
    text = P_OPEN_RE.sub(_para, text)
    return TAG_RE.sub(" ", text)


def process_book(cur, book_id):
    """Walk one book's pages. Returns markers, paragraphs, counts, stats."""
    marker_rows = []
    para_rows = []
    words = []
    pending = []
    counts = {e: 0 for e in EDITIONS}
    anomalies = []

    rows = cur.execute(
        "SELECT page, content FROM pages WHERE bookid=? ORDER BY page", (book_id,)
    ).fetchall()

    def flush(idx):
        for kind, num, page_no, marks, paras in pending:
            if kind == "m":
                ed, vol, pg = marks[num]
                counts[ed] += 1
                marker_rows.append((ed, vol, pg, page_no, idx))
            else:
                para_rows.append((paras[num], page_no, idx))
        del pending[:]

    for tpr_page, html in rows:
        if not html:
            continue
        marks, paras = [], []
        text = mark_page(html, marks, paras)
        for tok in tokenize(text, strip_html=False):
            hit = SENTINEL_RE.match(tok)
            if hit:
                pending.append((hit.group(1), int(hit.group(2)), tpr_page,
                                marks, paras))
                continue
            flush(len(words))
            words.append(tok)

    flush(len(words))   # sentinels trailing past the last word of the book

    out_markers = []
    for ed, vol, pg, tpr_page, idx in marker_rows:
        lo = max(0, idx - CONTEXT_WORDS)
        before = " ".join(words[lo:idx])
        after = " ".join(words[idx:idx + CONTEXT_WORDS])
        out_markers.append((book_id, ed, EDITIONS[ed], vol, pg, tpr_page, idx,
                            before, after))
        if not after:
            anomalies.append("%s%d.%d: marker past the last word" % (ed, vol, pg))
        if not before:
            anomalies.append("%s%d.%d: marker before the first word" % (ed, vol, pg))

    out_paras = [(book_id, cls, page_no, idx) for cls, page_no, idx in para_rows]

    # Within each edition page numbers should ascend. Where they do not, the
    # shape of the break matters, so classify rather than just count:
    #   repeat   - the same page anchored twice, often around a heading; the
    #              first occurrence is the start of that page
    #   restart  - numbering returns to a low page, i.e. a new printed volume
    #              sharing one TPR book
    #   back     - numbering steps backwards without restarting; worth a look
    for ed in EDITIONS:
        seq = [(v, p) for e, v, p, _, _ in marker_rows if e == ed]
        kinds = {"repeat": 0, "restart": 0, "back": 0}
        first = {}
        for a, b in zip(seq, seq[1:]):
            if b > a:
                continue
            kind = "repeat" if b == a else ("restart" if b[1] <= 2 else "back")
            kinds[kind] += 1
            first.setdefault(kind, (a, b))
        for kind, n in kinds.items():
            if not n:
                continue
            a, b = first[kind]
            anomalies.append("%s %s x%d (first: %d.%d after %d.%d)"
                             % (ed, kind, n, b[0], b[1], a[0], a[1]))

    return out_markers, out_paras, counts, len(words), len(rows), anomalies


def main():
    ap = argparse.ArgumentParser(
        description="Extract page markers and paragraph structure from the "
                    "original TPR database.")
    ap.add_argument("--source", required=True, help="path to tipitaka_pali.db")
    ap.add_argument("--out", default="original_markers.db", help="output database")
    ap.add_argument("--report", default="original_markers_report.txt")
    ap.add_argument("--books", help="comma-separated book ids (default: all)")
    args = ap.parse_args()

    if not os.path.exists(args.source):
        sys.exit("source database not found: " + args.source)

    src = sqlite3.connect("file:%s?mode=ro" % args.source.replace("\\", "/"), uri=True)
    cur = src.cursor()

    if args.books:
        book_ids = [b.strip() for b in args.books.split(",") if b.strip()]
    else:
        book_ids = [r[0] for r in cur.execute("SELECT id FROM books ORDER BY rowid")]

    if os.path.exists(args.out):
        os.remove(args.out)
    out = sqlite3.connect(args.out)
    out.executescript("""
        CREATE TABLE page_marker (
            book_id      TEXT NOT NULL,
            edition      TEXT NOT NULL,
            edition_name TEXT NOT NULL,
            vol          INTEGER NOT NULL,
            page         INTEGER NOT NULL,
            tpr_page     INTEGER NOT NULL,
            word_index   INTEGER NOT NULL,
            before_ctx   TEXT,
            after_ctx    TEXT
        );
        CREATE TABLE paragraph (
            book_id    TEXT NOT NULL,
            class      TEXT,
            tpr_page   INTEGER NOT NULL,
            word_index INTEGER NOT NULL
        );
        CREATE TABLE book_stat (
            book_id TEXT PRIMARY KEY,
            pages INTEGER, words INTEGER,
            m INTEGER, v INTEGER, p INTEGER, t INTEGER,
            paragraphs INTEGER, anomalies INTEGER
        );
    """)

    totals = {e: 0 for e in EDITIONS}
    report = []
    grand_words = grand_paras = grand_anom = books_with_anom = 0

    for book_id in book_ids:
        markers, paras, counts, nwords, npages, anomalies = process_book(cur, book_id)
        out.executemany("INSERT INTO page_marker VALUES (?,?,?,?,?,?,?,?,?)", markers)
        out.executemany("INSERT INTO paragraph VALUES (?,?,?,?)", paras)
        out.execute("INSERT INTO book_stat VALUES (?,?,?,?,?,?,?,?,?)", (
            book_id, npages, nwords, counts["M"], counts["V"],
            counts["P"], counts["T"], len(paras), len(anomalies)))
        for e in EDITIONS:
            totals[e] += counts[e]
        grand_words += nwords
        grand_paras += len(paras)
        grand_anom += len(anomalies)

        line = ("%-24s pages %5d  words %8d  M %5d V %5d P %5d T %5d  paras %6d"
                % (book_id, npages, nwords, counts["M"], counts["V"],
                   counts["P"], counts["T"], len(paras)))
        if anomalies:
            books_with_anom += 1
            line += "  ANOMALIES %d" % len(anomalies)
        report.append(line)
        for a in anomalies[:20]:
            report.append("    ! " + a)

    out.executescript("""
        CREATE INDEX idx_marker_book ON page_marker (book_id, edition, vol, page);
        CREATE INDEX idx_marker_pos  ON page_marker (book_id, word_index);
        CREATE INDEX idx_para_book   ON paragraph  (book_id, word_index);
    """)
    out.commit()

    header = [
        "Original TPR page markers and paragraph structure",
        "source: " + args.source,
        "books: %d   words: %d   paragraphs: %d" % (len(book_ids), grand_words, grand_paras),
        "page markers: " + "   ".join(
            "%s %d" % (EDITIONS[e], totals[e]) for e in ("M", "V", "P", "T")),
        "books with anomalies: %d   total anomalies: %d" % (books_with_anom, grand_anom),
        "",
    ]
    with open(args.report, "w", encoding="utf-8") as fh:
        fh.write("\n".join(header + report) + "\n")

    print("\n".join(header))
    print("wrote %s and %s" % (args.out, args.report))


if __name__ == "__main__":
    main()
