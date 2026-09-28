#!/usr/bin/env python3
"""
Work out which ePitaka book or books hold the text of each TPR book, by content.

ePitaka identifies books as 'D-i', 'Sp-i', 'Abhidh-s'; TPR uses 'mula_di_01'
and friends. Rather than maintain that correspondence by hand, this matches on
the Pali itself.

The naive form of that idea does not survive contact with the canon. Stock
formulas recur across the whole Tipitaka, so a short run of words taken from
the Digha will be found in the Majjhima, the Anguttara and several
commentaries. Counting matches per book therefore maps almost every book to
almost every other one.

What separates the real source from a formula is position. The ePitaka book
that actually holds a stretch of a TPR book matches it continuously, sample
after sample, in order. A formula matches one sample here and another there.
So each sampled position is assigned to a book by majority over a window of
neighbouring samples, and the answer is the sequence of runs that survives.
That also gives the multi-volume cases for free:

  * one ePitaka book covering several TPR volumes, as Sp-i covers
    attha_vi_01_01 and attha_vi_01_02;
  * one TPR book spanning several ePitaka books, in order.

Both databases are opened read-only.
"""

import argparse
import os
import sqlite3
import sys
from collections import Counter

from pali_text import tpr_word_stream, epitaka_word_stream

# Long enough that an ordinary sentence is distinctive, short enough to still
# match across the small wording differences between the two sources.
SHINGLE = 10
SAMPLES = 500
# Half-width of the voting window, in samples, used to smooth away formulas.
WINDOW = 6
# A run shorter than this is noise rather than a part of the book.
MIN_RUN = 3


def shingles(words, step=1):
    """Yield (position, key) for each run of SHINGLE consecutive words."""
    for i in range(0, len(words) - SHINGLE + 1, step):
        yield i, " ".join(words[i:i + SHINGLE])


def choose_runs(per_sample):
    """Turn per-sample candidate sets into an ordered list of runs.

    per_sample[i] is {epi_book: epi_position} for sample i, in TPR order.
    Each sample is assigned the book with most support in a window around it,
    which lets a continuously matching book outvote a passing formula.
    Returns [(epi_book, first_sample, last_sample, epi_first, epi_last), ...].
    """
    n = len(per_sample)
    assigned = [None] * n
    for i in range(n):
        if not per_sample[i]:
            continue
        votes = Counter()
        for j in range(max(0, i - WINDOW), min(n, i + WINDOW + 1)):
            for book in per_sample[j]:
                votes[book] += 1
        # only consider books that actually matched this sample
        best = max(per_sample[i], key=lambda b: (votes[b], -len(b)))
        assigned[i] = best

    runs = []
    start = None
    for i in range(n + 1):
        cur = assigned[i] if i < n else None
        if start is not None and (cur != assigned[start]):
            book = assigned[start]
            positions = [per_sample[k][book] for k in range(start, i)
                         if book in per_sample[k]]
            if positions and (i - start) >= MIN_RUN:
                runs.append((book, start, i - 1, min(positions), max(positions)))
            start = None
        if cur is not None and start is None:
            start = i
    return runs


def merge_runs(runs):
    """Join runs of the same book that are split by a short interruption."""
    merged = []
    for r in runs:
        if merged and merged[-1][0] == r[0]:
            p = merged[-1]
            merged[-1] = (p[0], p[1], r[2], min(p[3], r[3]), max(p[4], r[4]))
        else:
            merged.append(r)
    return merged


def main():
    ap = argparse.ArgumentParser(
        description="Map TPR books to the ePitaka books holding their text.")
    ap.add_argument("--tpr", required=True, help="path to tipitaka_pali.db")
    ap.add_argument("--epitaka", required=True, help="path to epitaka.db")
    ap.add_argument("--out", default="book_map.db")
    ap.add_argument("--report", default="book_map_report.txt")
    ap.add_argument("--books", help="comma-separated TPR book ids (default: all)")
    args = ap.parse_args()

    for p in (args.tpr, args.epitaka):
        if not os.path.exists(p):
            sys.exit("not found: " + p)

    tpr = sqlite3.connect("file:%s?mode=ro" % args.tpr.replace("\\", "/"), uri=True)
    tcur = tpr.cursor()
    book_ids = ([b.strip() for b in args.books.split(",")] if args.books else
                [r[0] for r in tcur.execute("SELECT id FROM books ORDER BY rowid")])

    print("sampling %d TPR books ..." % len(book_ids))
    samples = {}
    tpr_len = {}
    for book_id in book_ids:
        words = tpr_word_stream(tcur, book_id)
        tpr_len[book_id] = len(words)
        if len(words) < SHINGLE:
            samples[book_id] = []
            continue
        step = max(1, (len(words) - SHINGLE + 1) // SAMPLES)
        samples[book_id] = list(shingles(words, step))[:SAMPLES]
    print("  %d words total" % sum(tpr_len.values()))

    epi = sqlite3.connect("file:%s?mode=ro" % args.epitaka.replace("\\", "/"), uri=True)
    ecur = epi.cursor()
    epi_books = [r[0] for r in ecur.execute(
        "SELECT DISTINCT book_id FROM sentences ORDER BY book_id")]
    print("scanning %d ePitaka books ..." % len(epi_books))

    # per_sample[tpr_book][i] = {epi_book: epi_position}
    per_sample = {b: [dict() for _ in samples[b]] for b in samples}
    epi_len = {}
    for n, ebook in enumerate(epi_books, 1):
        ewords = epitaka_word_stream(ecur, ebook)[0]
        epi_len[ebook] = len(ewords)
        index = {}
        for i, key in shingles(ewords):
            if key not in index:
                index[key] = i
        for tbook, samp in samples.items():
            row = per_sample[tbook]
            for si, (ti, key) in enumerate(samp):
                ei = index.get(key)
                if ei is not None:
                    row[si][ebook] = ei
        if n % 40 == 0:
            print("  %d/%d" % (n, len(epi_books)), flush=True)

    if os.path.exists(args.out):
        os.remove(args.out)
    out = sqlite3.connect(args.out)
    out.executescript("""
        CREATE TABLE book_map (
            tpr_book  TEXT NOT NULL,
            seq       INTEGER NOT NULL,
            epi_book  TEXT NOT NULL,
            samples   INTEGER,          -- samples in this run
            tpr_first INTEGER, tpr_last INTEGER,   -- word offsets in the TPR book
            epi_first INTEGER, epi_last INTEGER,   -- word offsets in the ePitaka book
            tpr_words INTEGER, epi_words INTEGER,
            PRIMARY KEY (tpr_book, seq)
        );
        CREATE TABLE book_unmatched (tpr_book TEXT PRIMARY KEY, tpr_words INTEGER);
    """)

    rows, unmatched, report = [], [], []
    multi_epi, shared, weak = [], {}, []

    for tbook in book_ids:
        samp = samples[tbook]
        runs = merge_runs(choose_runs(per_sample[tbook]))
        if not runs:
            unmatched.append((tbook, tpr_len[tbook]))
            report.append("%-24s  NO MATCH  (%d words)" % (tbook, tpr_len[tbook]))
            continue
        covered = sum(r[2] - r[1] + 1 for r in runs) / max(len(samp), 1)
        for seq, (ebook, s0, s1, e0, e1) in enumerate(runs):
            rows.append((tbook, seq, ebook, s1 - s0 + 1,
                         samp[s0][0], samp[s1][0], e0, e1,
                         tpr_len[tbook], epi_len[ebook]))
            shared.setdefault(ebook, set()).add(tbook)
        if len({r[0] for r in runs}) > 1:
            multi_epi.append((tbook, [r[0] for r in runs]))
        if covered < 0.85:
            weak.append((tbook, covered, [r[0] for r in runs]))
        parts = "  +  ".join("%s [%d-%d]" % (r[0], samp[r[1]][0], samp[r[2]][0])
                             for r in runs)
        report.append("%-24s -> %s   covered %.1f%%" % (tbook, parts, 100 * covered))

    out.executemany("INSERT INTO book_map VALUES (?,?,?,?,?,?,?,?,?,?)", rows)
    out.executemany("INSERT INTO book_unmatched VALUES (?,?)", unmatched)
    out.commit()

    shared = {k: sorted(v) for k, v in shared.items() if len(v) > 1}
    header = [
        "Book mapping by text match, chosen by continuity rather than count",
        "TPR books: %d   ePitaka books: %d" % (len(book_ids), len(epi_books)),
        "mapped: %d   unmatched: %d" % (len(book_ids) - len(unmatched), len(unmatched)),
        "TPR books spanning more than one ePitaka book: %d" % len(multi_epi),
        "ePitaka books shared by more than one TPR book: %d" % len(shared),
        "books with under 85%% of samples covered: %d" % len(weak),
        "",
    ]
    if multi_epi:
        header.append("TPR books spanning several ePitaka books:")
        for t, es in multi_epi:
            header.append("  %-24s %s" % (t, " + ".join(es)))
        header.append("")
    if shared:
        header.append("ePitaka books shared by several TPR books:")
        for e, ts in sorted(shared.items()):
            header.append("  %-14s %s" % (e, ", ".join(ts)))
        header.append("")
    if weak:
        header.append("Under 85%% covered, check these:")
        for t, c, es in weak:
            header.append("  %-24s %.1f%%  %s" % (t, 100 * c, " + ".join(es)))
        header.append("")
    if unmatched:
        header.append("No match at all:")
        for t, w in unmatched:
            header.append("  %-24s %d words" % (t, w))
        header.append("")

    with open(args.report, "w", encoding="utf-8") as fh:
        fh.write("\n".join(header + report) + "\n")
    print("\n".join(header[:8]))
    print("wrote %s and %s" % (args.out, args.report))


if __name__ == "__main__":
    main()
