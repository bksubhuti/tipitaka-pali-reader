#!/usr/bin/env python3
"""
Build the search units for the migrated data, and measure what changes.

TPR's phrase search works today because the indexed unit is larger than a
sentence: the whole of a printed page is indexed as one continuous string, so a
phrase running across a sentence boundary still matches. Indexing single
sentences instead would lose that, and indexing single paragraphs would shorten
the reach of distance search, since a paragraph averages about forty words
against a page's two hundred.

So a unit here is a run of whole paragraphs of roughly page size, and
consecutive units overlap by one paragraph. Boundaries fall only between
paragraphs, never inside a sentence, and nothing falls between two units.

The measurement at the end is the point of the exercise. A phrase that straddles
a printed page break cannot be found today unless it happens to recur
elsewhere, because the unit follows the printer's pagination. The same phrases
are tested against the new units, which follow the text's own structure.
"""

import argparse
import os
import re
import sqlite3
import sys

from pali_text import tokenize, tpr_word_stream

TAG_RE = re.compile(r"<[^>]*>")
TARGET_WORDS = 200          # a printed page, near enough
OVERLAP_PARAS = 1
JUNCTION_WORDS = 3          # words taken from each side of a page break


def build_units(ecur, book_id):
    """Group a book's sentences into overlapping, page-sized units."""
    paras = {}
    order = []
    for para_id, line_id, pali in ecur.execute(
            "SELECT para_id, line_id, pali FROM sentences WHERE book_id=? "
            "ORDER BY para_id, line_id", (book_id,)):
        if not pali:
            continue
        if para_id not in paras:
            paras[para_id] = []
            order.append(para_id)
        paras[para_id].append(pali)

    units = []
    i = 0
    while i < len(order):
        chunk, words, j = [], 0, i
        while j < len(order) and (not chunk or words < TARGET_WORDS):
            text = " ".join(paras[order[j]])
            chunk.append(order[j])
            words += len(tokenize(text, strip_html=False))
            j += 1
        content = " ".join(" ".join(paras[p]) for p in chunk)
        units.append((book_id, chunk[0], chunk[-1], words, content))
        if j >= len(order):
            break
        i = max(i + 1, j - OVERLAP_PARAS)
    return units


def junction_phrases(tcur, book_id):
    """Phrases that straddle a printed page break in the original."""
    rows = tcur.execute(
        "SELECT page, content FROM pages WHERE bookid=? ORDER BY page",
        (book_id,)).fetchall()
    out = []
    prev = None
    for page, html in rows:
        words = tokenize(html)
        if not words:
            continue
        if prev:
            phrase = prev[-JUNCTION_WORDS:] + words[:JUNCTION_WORDS]
            if len(phrase) == JUNCTION_WORDS * 2:
                out.append((page, " ".join(phrase)))
        prev = words
    return out


def main():
    ap = argparse.ArgumentParser(
        description="Build overlapping paragraph-based search units and "
                    "measure page-junction phrase findability.")
    ap.add_argument("--epitaka", required=True)
    ap.add_argument("--tpr", required=True)
    ap.add_argument("--map", dest="bookmap", default="book_map.db")
    ap.add_argument("--out", default="fts_units.db")
    ap.add_argument("--report", default="fts_report.txt")
    ap.add_argument("--measure-books", default="mula_di_01,mula_ma_01,attha_di_01",
                    help="TPR books to run the junction measurement on")
    args = ap.parse_args()

    for p in (args.epitaka, args.tpr, args.bookmap):
        if not os.path.exists(p):
            sys.exit("not found: " + p)

    epi = sqlite3.connect("file:%s?mode=ro" % args.epitaka.replace("\\", "/"), uri=True)
    tpr = sqlite3.connect("file:%s?mode=ro" % args.tpr.replace("\\", "/"), uri=True)
    bm = sqlite3.connect("file:%s?mode=ro" % args.bookmap.replace("\\", "/"), uri=True)
    ecur, tcur = epi.cursor(), tpr.cursor()

    if os.path.exists(args.out):
        os.remove(args.out)
    out = sqlite3.connect(args.out)
    out.executescript("""
        CREATE TABLE unit (
            id INTEGER PRIMARY KEY,
            book_id TEXT NOT NULL,
            first_para INTEGER, last_para INTEGER,
            words INTEGER, content TEXT
        );
    """)

    epi_books = [r[0] for r in ecur.execute(
        "SELECT DISTINCT book_id FROM sentences ORDER BY book_id")]
    total_units = total_words = 0
    print("building units for %d ePitaka books ..." % len(epi_books))
    for n, book in enumerate(epi_books, 1):
        units = build_units(ecur, book)
        out.executemany(
            "INSERT INTO unit (book_id, first_para, last_para, words, content) "
            "VALUES (?,?,?,?,?)", units)
        total_units += len(units)
        total_words += sum(u[3] for u in units)
        if n % 50 == 0:
            print("  %d/%d" % (n, len(epi_books)), flush=True)
    out.commit()

    # The measurement: page-junction phrases, before and after.
    report = []
    meas_books = [b.strip() for b in args.measure_books.split(",") if b.strip()]
    tot_j = tot_before = tot_after = 0
    for tbook in meas_books:
        ebooks = [r[0] for r in bm.execute(
            "SELECT epi_book FROM book_map WHERE tpr_book=? ORDER BY seq", (tbook,))]
        if not ebooks:
            report.append("%-20s not mapped, skipped" % tbook)
            continue

        # today's unit: one printed page of the original
        pages = [" ".join(tokenize(h)) for (h,) in tcur.execute(
            "SELECT content FROM pages WHERE bookid=? ORDER BY page", (tbook,))]
        page_blob = "\n".join(pages)

        # the new unit
        new_units = []
        for eb in ebooks:
            new_units.extend(" ".join(tokenize(u[0], strip_html=False))
                             for u in out.execute(
                                 "SELECT content FROM unit WHERE book_id=?", (eb,)))
        new_blob = "\n".join(new_units)

        found_before = found_after = 0
        phrases = junction_phrases(tcur, tbook)
        for _, phrase in phrases:
            if phrase in page_blob:
                found_before += 1
            if phrase in new_blob:
                found_after += 1
        tot_j += len(phrases)
        tot_before += found_before
        tot_after += found_after
        report.append(
            "%-20s junctions %4d   findable today %4d (%5.1f%%)   "
            "findable after %4d (%5.1f%%)"
            % (tbook, len(phrases), found_before,
               100.0 * found_before / max(len(phrases), 1), found_after,
               100.0 * found_after / max(len(phrases), 1)))
        print(report[-1], flush=True)

    out.executescript("CREATE INDEX idx_unit_book ON unit (book_id, first_para);")
    out.commit()

    header = [
        "Search units: whole paragraphs grouped to about %d words, "
        "overlapping by %d" % (TARGET_WORDS, OVERLAP_PARAS),
        "units: %d   average words per unit: %.0f"
        % (total_units, total_words / max(total_units, 1)),
        "",
        "Page-junction phrases (%d words either side of a printed page break):"
        % JUNCTION_WORDS,
        "  measured on %d books: %d junctions, %d findable today (%.1f%%), "
        "%d findable after (%.1f%%)"
        % (len(meas_books), tot_j, tot_before, 100.0 * tot_before / max(tot_j, 1),
           tot_after, 100.0 * tot_after / max(tot_j, 1)),
        "",
    ]
    with open(args.report, "w", encoding="utf-8") as fh:
        fh.write("\n".join(header + report) + "\n")
    print("\n".join(header))
    print("wrote %s and %s" % (args.out, args.report))


if __name__ == "__main__":
    main()
