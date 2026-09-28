#!/usr/bin/env python3
"""
Write the review report for the places the migration was not certain.

The whole build was done in one pass rather than in stages, on the
understanding that two things would be looked at by a person afterwards:
where a page boundary or a page marker landed on text the two sources spell
differently, and where a book's page numbering does not simply ascend.

A count does not let anyone judge those. This puts each case next to the words
around it, from both sources, so the question "is that the right place?" can
actually be answered by reading it.

Pages are the important half. A page boundary an inch out moves where a page
begins; a page marker an inch out moves a small badge. Boundaries are reported
first and in full, markers are summarised.
"""

import argparse
import os
import re
import sqlite3
import sys

CONTEXT = 7
TAG = re.compile(r"<[^>]*>")


def words_of(text):
    return TAG.sub(" ", text or "").split()


def sentence_context(epi, book, para, line, offset):
    """The words around a position inside an ePitaka sentence."""
    row = epi.execute(
        "SELECT pali FROM sentences WHERE book_id=? AND para_id=? AND line_id=?",
        (book, para, line)).fetchone()
    if not row:
        return "", ""
    w = words_of(row[0])
    lo = max(0, offset - CONTEXT)
    return " ".join(w[lo:offset]), " ".join(w[offset:offset + CONTEXT])


def original_context(markers, book, edition, vol, page):
    row = markers.execute(
        "SELECT before_ctx, after_ctx FROM page_marker "
        "WHERE book_id=? AND edition=? AND vol=? AND page=? LIMIT 1",
        (book, edition, vol, page)).fetchone()
    return (row[0] or "", row[1] or "") if row else ("", "")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--extension", default="tpr_extension.db")
    ap.add_argument("--epitaka", default="epitaka.db")
    ap.add_argument("--markers", default="original_markers.db")
    ap.add_argument("--tpr", required=True)
    ap.add_argument("--out", default="review_report.txt")
    ap.add_argument("--detail", type=int, default=60,
                    help="how many boundaries to show in full per book")
    args = ap.parse_args()

    for p in (args.extension, args.epitaka, args.markers, args.tpr):
        if not os.path.exists(p):
            sys.exit("not found: " + p)

    ro = lambda p: sqlite3.connect("file:%s?mode=ro" % p.replace("\\", "/"),
                                   uri=True)
    ext, epi = ro(args.extension), ro(args.epitaka)
    markers, tpr = ro(args.markers), ro(args.tpr)

    out = []
    w = out.append

    breaks = ext.execute(
        "SELECT tpr_book, tpr_page, book_id, para_id, line_id, word_index "
        "FROM page_break WHERE exact=0 ORDER BY tpr_book, tpr_page").fetchall()
    # page_mark is keyed by the ePitaka book; the reader knows TPR books, so
    # each is resolved back through the page it falls on.
    marks = ext.execute('''
        SELECT (SELECT b.tpr_book FROM page_break b
                WHERE b.book_id = m.book_id AND b.para_id <= m.para_id
                ORDER BY b.para_id DESC LIMIT 1) AS tpr_book,
               m.book_id, m.para_id, m.line_id, m.edition, m.vol, m.page,
               m.word_index
        FROM page_mark m WHERE m.exact = 0
        ORDER BY tpr_book, m.edition, m.vol, m.page''').fetchall()

    total_breaks = ext.execute(
        "SELECT count(*) FROM page_break").fetchone()[0]
    total_marks = ext.execute("SELECT count(*) FROM page_mark").fetchone()[0]

    w("Review report: the places the migration was not certain")
    w("=" * 70)
    w("")
    w("Page boundaries placed on differing text: %d of %d (%.2f%%)"
      % (len(breaks), total_breaks, 100.0 * len(breaks) / max(total_breaks, 1)))
    w("Page markers placed on differing text:    %d of %d (%.2f%%)"
      % (len(marks), total_marks, 100.0 * len(marks) / max(total_marks, 1)))
    w("")
    w("A boundary decides where a page begins, so those are given in full.")
    w("A marker only decides where a small page-number badge sits, so those")
    w("are summarised by book.")
    w("")
    w("For each case: what the original TPR text has at that point, then what")
    w("sits at the position chosen in ePitaka. If the two read the same, the")
    w("placement is right even though the words around it differ.")
    w("")

    by_book = {}
    for row in breaks:
        by_book.setdefault(row[0], []).append(row)

    w("")
    w("PAGE BOUNDARIES")
    w("=" * 70)
    for book in sorted(by_book, key=lambda b: -len(by_book[b])):
        rows = by_book[book]
        name = tpr.execute("SELECT name FROM books WHERE id=?",
                           (book,)).fetchone()
        w("")
        w("%s  %s" % (book, name[0] if name else ""))
        w("  %d boundaries to check" % len(rows))
        for tpr_book, page, epi_book, para, line, offset in rows[:args.detail]:
            original = tpr.execute(
                "SELECT content FROM pages WHERE bookid=? AND page=?",
                (tpr_book, page)).fetchone()
            first = " ".join(words_of(original[0])[:CONTEXT]) if original else ""
            before, after = sentence_context(epi, epi_book, para, line, offset)
            w("")
            w("    page %-5d  TPR page begins: %s" % (page, first))
            w("               placed at:      %s | %s" % (before, after))
        if len(rows) > args.detail:
            w("")
            w("    ... and %d more in this book" % (len(rows) - args.detail))

    w("")
    w("")
    w("PAGE MARKERS")
    w("=" * 70)
    marks_by_book = {}
    for row in marks:
        marks_by_book.setdefault(row[0] or '(no TPR page)', []).append(row)
    editions = {"M": "myanmar", "V": "vri", "P": "pts", "T": "thai"}
    for book in sorted(marks_by_book, key=lambda b: -len(marks_by_book[b])):
        rows = marks_by_book[book]
        counts = {}
        for r in rows:
            counts[r[4]] = counts.get(r[4], 0) + 1
        w("  %-22s %4d  (%s)" % (book, len(rows), ", ".join(
            "%s %d" % (editions.get(e, e), n) for e, n in sorted(counts.items()))))
        sample = rows[0]
        before, after = sentence_context(epi, sample[1], sample[2], sample[3],
                                         sample[7])
        ob, oa = original_context(
            markers, sample[0] or book, sample[4], sample[5], sample[6])
        w("      e.g. %s%d.%d" % (sample[4], sample[5], sample[6]))
        w("        original: %s | %s" % (ob, oa))
        w("        placed:   %s | %s" % (before, after))

    w("")
    w("")
    w("PAGE NUMBERING THAT DOES NOT SIMPLY ASCEND")
    w("=" * 70)
    w("")
    w("Repeats are usually the same page anchored twice around a heading, and")
    w("are handled by taking the first. Restarts are a second printed volume")
    w("inside one TPR book. Steps backwards are the ones worth a look.")
    w("")
    report = os.path.join(os.path.dirname(args.markers) or ".",
                          "original_markers_report.txt")
    if os.path.exists(report):
        with open(report, encoding="utf-8") as fh:
            keep = False
            for line in fh:
                if "ANOMALIES" in line:
                    keep = True
                    w("  " + line.rstrip())
                elif keep and line.startswith("    !"):
                    w("  " + line.rstrip())
                else:
                    keep = False
    else:
        w("  (original_markers_report.txt not found)")

    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")
    print("\n".join(out[:12]))
    print("...")
    print("wrote %s (%d lines)" % (args.out, len(out)))


if __name__ == "__main__":
    main()
