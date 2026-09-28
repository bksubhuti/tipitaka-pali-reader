#!/usr/bin/env python3
"""
Carry the page markers and paragraph structure of the original TPR database
onto ePitaka's sentences.

Input is original_markers.db (from extract_original.py) and book_map.db (from
map_books.py). For each mapped book the two word streams are aligned, and every
marker's word offset is carried through the alignment onto an ePitaka sentence
and an offset within it.

Alignment rather than search: the two texts are the same Pali, differing only
in local details such as where a quotation mark sits. Aligning the whole book
places every marker in one pass and, more usefully, says plainly which markers
landed on identical text and which did not. A marker inside a differing stretch
is written with exact = 0 and listed in the report; it is never quietly moved
to the start of a sentence, which is the rounding this work exists to remove.

Output is sentence_ext.db:

    page_mark(book_id, para_id, line_id, edition, vol, page, word_index, exact)
    glue(book_id, para_id, line_id, state)      -- continue / paragraph / verse

Both source databases are opened read-only.
"""

import argparse
import bisect
import difflib
import os
import sqlite3
import sys
import time

from pali_text import tpr_word_stream, epitaka_word_stream

# Paragraph classes in the original that mean "this is not a new prose
# paragraph". A sentence whose text continues one of these must be kept with
# what precedes it when the reader rebuilds paragraphs.
CONTINUATION_CLASSES = {"noindentbodytext"}
VERSE_PREFIX = "gatha"


def align(tpr_words, epi_words):
    """Map TPR word positions onto ePitaka word positions.

    Returns (exact, approx). `exact` maps a TPR index to an ePitaka index where
    the surrounding text is identical. `approx` covers the rest: it maps to the
    ePitaka position implied by the nearest preceding identical stretch, which
    is a reasonable placement but is reported as inexact.
    """
    sm = difflib.SequenceMatcher(a=tpr_words, b=epi_words, autojunk=False)
    exact = {}
    starts = []          # (tpr_start, epi_start, size) of identical stretches
    for blk in sm.get_matching_blocks():
        if not blk.size:
            continue
        starts.append((blk.a, blk.b, blk.size))
        for k in range(blk.size):
            exact[blk.a + k] = blk.b + k
    return exact, starts


def approximate(index, starts, starts_keys, epi_len):
    """Place a TPR index that fell outside every identical stretch."""
    i = bisect.bisect_right(starts_keys, index) - 1
    if i < 0:
        return 0
    a, b, size = starts[i]
    return min(epi_len - 1, b + (index - a))


def main():
    ap = argparse.ArgumentParser(
        description="Carry TPR page markers and paragraph structure onto "
                    "ePitaka sentences.")
    ap.add_argument("--tpr", required=True)
    ap.add_argument("--epitaka", required=True)
    ap.add_argument("--markers", default="original_markers.db")
    ap.add_argument("--map", dest="bookmap", default="book_map.db")
    ap.add_argument("--out", default="sentence_ext.db")
    ap.add_argument("--report", default="match_report.txt")
    ap.add_argument("--books", help="comma-separated TPR book ids (default: all mapped)")
    args = ap.parse_args()

    for p in (args.tpr, args.epitaka, args.markers, args.bookmap):
        if not os.path.exists(p):
            sys.exit("not found: " + p)

    tprdb = sqlite3.connect("file:%s?mode=ro" % args.tpr.replace("\\", "/"), uri=True)
    epidb = sqlite3.connect("file:%s?mode=ro" % args.epitaka.replace("\\", "/"), uri=True)
    mk = sqlite3.connect("file:%s?mode=ro" % args.markers.replace("\\", "/"), uri=True)
    bm = sqlite3.connect("file:%s?mode=ro" % args.bookmap.replace("\\", "/"), uri=True)

    # A TPR book can span several ePitaka books; take them in order.
    plan = {}
    for tbook, ebook in bm.execute(
            "SELECT tpr_book, epi_book FROM book_map ORDER BY tpr_book, seq"):
        plan.setdefault(tbook, []).append(ebook)
    if args.books:
        want = {b.strip() for b in args.books.split(",")}
        plan = {k: v for k, v in plan.items() if k in want}
    pairs = sorted(plan.items())
    if not pairs:
        sys.exit("no mapped books to process")

    if os.path.exists(args.out):
        os.remove(args.out)
    out = sqlite3.connect(args.out)
    out.executescript("""
        CREATE TABLE page_mark (
            book_id TEXT NOT NULL, para_id INTEGER NOT NULL, line_id INTEGER NOT NULL,
            edition TEXT NOT NULL, vol INTEGER, page INTEGER,
            word_index INTEGER NOT NULL,   -- offset within the sentence
            exact INTEGER NOT NULL,        -- 1 = landed on identical text
            tpr_book TEXT
        );
        CREATE TABLE glue (
            book_id TEXT NOT NULL, para_id INTEGER NOT NULL, line_id INTEGER NOT NULL,
            state TEXT NOT NULL            -- continue / paragraph / verse
        );
        CREATE TABLE book_stat (
            tpr_book TEXT PRIMARY KEY, epi_book TEXT,
            tpr_words INTEGER, epi_words INTEGER, aligned_pct REAL,
            markers INTEGER, markers_exact INTEGER,
            m INTEGER, v INTEGER, p INTEGER, t INTEGER,
            glue_rows INTEGER, seconds REAL
        );
    """)

    report = []
    tot_markers = tot_exact = 0
    t_start = time.time()

    for n, (tbook, ebooks) in enumerate(pairs, 1):
        t0 = time.time()
        tw = tpr_word_stream(tprdb.cursor(), tbook)
        ew, spans = [], []
        for eb in ebooks:
            w, sp = epitaka_word_stream(epidb.cursor(), eb)
            ew.extend(w)
            spans.extend((eb, p, l, o) for p, l, o in sp)
        ebook = " + ".join(ebooks)
        if not tw or not ew:
            report.append("%-24s -> %-14s  EMPTY, skipped" % (tbook, ebook))
            continue

        exact, starts = align(tw, ew)
        starts_keys = [s[0] for s in starts]
        aligned_pct = 100.0 * len(exact) / len(tw)

        # page markers
        rows = []
        counts = {"M": 0, "V": 0, "P": 0, "T": 0}
        n_exact = 0
        inexact_examples = []
        for ed, vol, page, widx in mk.execute(
                "SELECT edition, vol, page, word_index FROM page_marker "
                "WHERE book_id=? ORDER BY word_index", (tbook,)):
            if widx in exact:
                epi_i = exact[widx]
                is_exact = 1
                n_exact += 1
            else:
                epi_i = approximate(widx, starts, starts_keys, len(ew))
                is_exact = 0
                if len(inexact_examples) < 10:
                    inexact_examples.append("%s%d.%d" % (ed, vol, page))
            if epi_i >= len(spans):
                epi_i = len(spans) - 1
            eb, para_id, line_id, offset = spans[epi_i]
            counts[ed] = counts.get(ed, 0) + 1
            rows.append((eb, para_id, line_id, ed, vol, page, offset,
                         is_exact, tbook))
        out.executemany(
            "INSERT INTO page_mark VALUES (?,?,?,?,?,?,?,?,?)", rows)

        # paragraph structure -> glue state on the sentence that starts there
        grows = []
        seen = set()
        for cls, widx in mk.execute(
                "SELECT class, word_index FROM paragraph WHERE book_id=? "
                "ORDER BY word_index", (tbook,)):
            epi_i = exact.get(widx)
            if epi_i is None:
                epi_i = approximate(widx, starts, starts_keys, len(ew))
            if epi_i >= len(spans):
                continue
            eb, para_id, line_id, _ = spans[epi_i]
            key = (eb, para_id, line_id)
            if key in seen:
                continue
            seen.add(key)
            cls = cls or ""
            if cls.startswith(VERSE_PREFIX):
                state = "verse"
            elif cls in CONTINUATION_CLASSES:
                state = "continue"
            else:
                state = "paragraph"
            grows.append((eb, para_id, line_id, state))
        out.executemany("INSERT INTO glue VALUES (?,?,?,?)", grows)

        dt = time.time() - t0
        out.execute("INSERT INTO book_stat VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", (
            tbook, ebook, len(tw), len(ew), aligned_pct, len(rows), n_exact,
            counts.get("M", 0), counts.get("V", 0), counts.get("P", 0),
            counts.get("T", 0), len(grows), dt))
        out.commit()

        tot_markers += len(rows)
        tot_exact += n_exact
        line = ("%-24s -> %-14s aligned %5.1f%%  markers %5d exact %5d (%5.1f%%)"
                "  glue %6d  %4.0fs"
                % (tbook, ebook, aligned_pct, len(rows), n_exact,
                   100.0 * n_exact / max(len(rows), 1), len(grows), dt))
        report.append(line)
        if inexact_examples:
            report.append("     inexact: " + ", ".join(inexact_examples))
        print("[%3d/%3d] %s" % (n, len(pairs), line), flush=True)

    out.executescript("""
        CREATE INDEX idx_mark ON page_mark (book_id, para_id, line_id);
        CREATE INDEX idx_glue ON glue (book_id, para_id, line_id);
    """)
    out.commit()

    header = [
        "Page markers and paragraph structure carried onto ePitaka sentences",
        "books: %d" % len(pairs),
        "markers: %d   placed on identical text: %d (%.2f%%)"
        % (tot_markers, tot_exact, 100.0 * tot_exact / max(tot_markers, 1)),
        "total time: %.0f minutes" % ((time.time() - t_start) / 60),
        "",
        "A marker that did not land on identical text is written with exact=0",
        "and named above. Those are the ones to look at; nothing is silently",
        "moved to the start of a sentence.",
        "",
    ]
    with open(args.report, "w", encoding="utf-8") as fh:
        fh.write("\n".join(header + report) + "\n")
    print("\n".join(header))
    print("wrote %s and %s" % (args.out, args.report))


if __name__ == "__main__":
    main()
