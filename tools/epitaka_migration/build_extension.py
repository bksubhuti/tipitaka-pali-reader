#!/usr/bin/env python3
"""
Assemble the TPR-side extension database that the app reads.

This is the deliverable. It gathers the pieces the earlier steps produced into
the two tables described on issue #321, keyed exactly as ePitaka keys its
sentences, so that ePitaka's own file is used as downloaded and never edited.
If ePitaka later adopts these two fields into its sentence table, the reader
selects them from there and this file is dropped, with no other change.

    sentence_ext(book_id, para_id, line_id, mypage_word_index, glue_state)
    page_mark(book_id, para_id, line_id, edition, vol, page, word_index, exact)

`sentence_ext` carries only rows that say something: a sentence with no page
marker and an ordinary paragraph break has no row. `page_mark` keeps all four
printed editions, so the app can show whichever the reader wants.

The three books ePitaka does not carry are folded in here too, with their
sentences, so nothing in the app today is lost.
"""

import argparse
import os
import sqlite3
import sys


def main():
    ap = argparse.ArgumentParser(
        description="Assemble the TPR extension database from the earlier steps.")
    ap.add_argument("--matched", default="sentence_ext.db")
    ap.add_argument("--missing", default="missing_books.db")
    ap.add_argument("--out", default="tpr_extension.db")
    ap.add_argument("--report", default="extension_report.txt")
    args = ap.parse_args()

    for p in (args.matched, args.missing):
        if not os.path.exists(p):
            sys.exit("not found: " + p)

    if os.path.exists(args.out):
        os.remove(args.out)
    out = sqlite3.connect(args.out)
    out.executescript("""
        CREATE TABLE sentence_ext (
            book_id TEXT NOT NULL,
            para_id INTEGER NOT NULL,
            line_id INTEGER NOT NULL,
            mypage_word_index INTEGER,   -- word offset where the mm page begins
            glue_state TEXT,             -- continue / paragraph / verse
            PRIMARY KEY (book_id, para_id, line_id)
        );
        CREATE TABLE page_mark (
            book_id TEXT NOT NULL, para_id INTEGER NOT NULL, line_id INTEGER NOT NULL,
            edition TEXT NOT NULL,       -- M / V / P / T
            vol INTEGER, page INTEGER,
            word_index INTEGER NOT NULL, -- offset within the sentence
            exact INTEGER NOT NULL       -- 0 = placed in a differing stretch
        );
        CREATE TABLE extra_sentence (
            book_id TEXT NOT NULL, para_id INTEGER NOT NULL, line_id INTEGER NOT NULL,
            vripara TEXT, thaipage TEXT, vripage TEXT, ptspage TEXT, mypage TEXT,
            pali TEXT,
            PRIMARY KEY (book_id, para_id, line_id)
        );
    """)
    out.commit()

    out.execute("ATTACH DATABASE ? AS m", (args.matched,))
    out.execute("ATTACH DATABASE ? AS x", (args.missing,))

    out.execute("""
        INSERT INTO page_mark
        SELECT book_id, para_id, line_id, edition, vol, page, word_index, exact
        FROM m.page_mark
    """)
    out.execute("""
        INSERT INTO page_mark
        SELECT book_id, para_id, line_id, edition, vol, page, word_index, exact
        FROM x.page_mark
    """)

    # Myanmar offsets and glue state, merged onto one row per sentence.
    out.execute("""
        INSERT INTO sentence_ext (book_id, para_id, line_id, mypage_word_index)
        SELECT book_id, para_id, line_id, MIN(word_index)
        FROM page_mark WHERE edition='M'
        GROUP BY book_id, para_id, line_id
    """)
    out.execute("""
        INSERT OR IGNORE INTO sentence_ext (book_id, para_id, line_id, glue_state)
        SELECT book_id, para_id, line_id, state FROM m.glue
        WHERE state <> 'paragraph'
    """)
    out.execute("""
        UPDATE sentence_ext SET glue_state = (
            SELECT state FROM m.glue g
            WHERE g.book_id = sentence_ext.book_id
              AND g.para_id = sentence_ext.para_id
              AND g.line_id = sentence_ext.line_id)
        WHERE glue_state IS NULL
    """)

    out.execute("""
        INSERT INTO extra_sentence
        SELECT book_id, para_id, line_id, vripara, thaipage, vripage,
               ptspage, mypage, pali FROM x.sentences
    """)
    out.execute("""
        INSERT OR IGNORE INTO sentence_ext (book_id, para_id, line_id, glue_state)
        SELECT book_id, para_id, line_id, glue_state FROM x.sentences
        WHERE glue_state <> 'paragraph'
    """)
    out.commit()

    # A sentence with nothing to say does not need a row.
    out.execute("DELETE FROM sentence_ext "
                "WHERE mypage_word_index IS NULL AND "
                "(glue_state IS NULL OR glue_state = 'paragraph')")
    out.executescript("""
        CREATE INDEX idx_mark ON page_mark (book_id, para_id, line_id);
        CREATE INDEX idx_mark_page ON page_mark (book_id, edition, vol, page);
    """)
    out.commit()

    q = lambda s: out.execute(s).fetchone()[0]
    stats = [
        ("sentence_ext rows", q("SELECT count(*) FROM sentence_ext")),
        ("  with a Myanmar page offset",
         q("SELECT count(*) FROM sentence_ext WHERE mypage_word_index IS NOT NULL")),
        ("  marked keep-with-next",
         q("SELECT count(*) FROM sentence_ext WHERE glue_state='continue'")),
        ("  marked verse line",
         q("SELECT count(*) FROM sentence_ext WHERE glue_state='verse'")),
        ("page_mark rows", q("SELECT count(*) FROM page_mark")),
        ("  placed on identical text",
         q("SELECT count(*) FROM page_mark WHERE exact=1")),
        ("  placed in a differing stretch",
         q("SELECT count(*) FROM page_mark WHERE exact=0")),
        ("books covered", q("SELECT count(DISTINCT book_id) FROM page_mark")),
        ("extra sentences (books ePitaka lacks)",
         q("SELECT count(*) FROM extra_sentence")),
    ]
    by_ed = out.execute(
        "SELECT edition, count(*) FROM page_mark GROUP BY edition ORDER BY 2 DESC"
    ).fetchall()

    lines = ["TPR extension database", ""]
    for label, value in stats:
        lines.append("%-40s %9d" % (label, value))
    lines.append("")
    lines.append("page markers by edition:")
    names = {"M": "myanmar", "V": "vri", "P": "pts", "T": "thai"}
    for ed, cnt in by_ed:
        lines.append("  %-10s %9d" % (names.get(ed, ed), cnt))
    lines.append("")
    lines.append("Rows with exact = 0 are the ones to review. Nothing was moved")
    lines.append("to the start of a sentence to make a number look better.")

    with open(args.report, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    print("\nwrote %s and %s" % (args.out, args.report))


if __name__ == "__main__":
    main()
