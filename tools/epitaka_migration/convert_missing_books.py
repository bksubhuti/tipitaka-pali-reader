#!/usr/bin/env python3
"""
Build ePitaka-shaped sentences for the TPR books that ePitaka does not carry.

Three books in TPR have no counterpart in ePitaka: the Saddaniti suttamala,
the Saddatthabhedacinta and the Kaccayanasara. Their text is the same VRI
material as everything else, and TPR already holds it, so they are converted
here rather than being lost or fetched again.

The conversion follows what ePitaka does elsewhere, checked against its own
data rather than guessed:

  * one paragraph of the original becomes one para_id, numbered from 1;
  * each sentence inside a paragraph becomes a line_id, numbered from 1;
  * a printed edition's page number is recorded on the sentence where that
    page begins, written as 'vol.page' exactly as ePitaka writes it.

Because the sentences are built here, the page positions are known outright
instead of being matched, so every marker for these books is exact.

Capitalisation: TPR stores this text in lower case throughout, while ePitaka
capitalises the first letter of a sentence. The default is to follow ePitaka,
so that these books look like every other book once migrated. Pass
--no-capitalise to keep TPR's own casing. Only the first letter is touched;
no word is altered and nothing is reordered.
"""

import argparse
import os
import re
import sqlite3
import sys

from pali_text import tokenize

# Default set: the books found to be absent from ePitaka.
DEFAULT_BOOKS = ["annya_sadda_09", "annya_sadda_16", "annya_sadda_17"]

ANCHOR_RE = re.compile(r'<a\s+name="([MVPT])(\d+)\.(\d+)"[^>]*>\s*</a\s*>', re.I)
P_BLOCK_RE = re.compile(r'<p\b([^>]*)>(.*?)</p\s*>', re.I | re.S)
P_CLASS_RE = re.compile(r'class="([^"]*)"', re.I)
TAG_RE = re.compile(r"<[^>]*>")
WS_RE = re.compile(r"\s+")

# Split after a full stop, question or exclamation mark followed by space.
# A stop that closes a leading number is not a sentence end: paragraph and
# verse numbering such as "12. " opens a sentence rather than ending one.
SENT_SPLIT_RE = re.compile(r"(?<=[.?!‘’\"])\s+")
LEADING_NUM_RE = re.compile(r"^[\d,\s]*\.?$")

EDITION_COLUMN = {"M": "mypage", "V": "vripage", "P": "ptspage", "T": "thaipage"}

MARK = ""


def split_sentences(text):
    """Split a paragraph into sentences, ePitaka style."""
    parts = [p for p in SENT_SPLIT_RE.split(text) if p.strip()]
    merged = []
    for part in parts:
        # a fragment that is only a number and a stop belongs to what follows
        if merged and LEADING_NUM_RE.match(merged[-1].strip()):
            merged[-1] = merged[-1].rstrip() + " " + part
        else:
            merged.append(part)
    return [WS_RE.sub(" ", p).strip() for p in merged if p.strip()]


def capitalise(text):
    for i, ch in enumerate(text):
        if ch.isalpha():
            return text[:i] + ch.upper() + text[i + 1:]
    return text


def convert_book(cur, book_id, do_caps):
    """Return (sentence rows, marker rows) for one TPR book."""
    sentences = []
    markers = []
    para_id = 0

    for tpr_page, html in cur.execute(
            "SELECT page, content FROM pages WHERE bookid=? ORDER BY page", (book_id,)):
        if not html:
            continue
        for m in P_BLOCK_RE.finditer(html):
            attrs, body = m.group(1), m.group(2)
            cls_m = P_CLASS_RE.search(attrs or "")
            cls = cls_m.group(1) if cls_m else ""

            # keep the anchors as sentinels so their position survives cleaning
            found = []

            def _anchor(mm):
                found.append((mm.group(1).upper(), int(mm.group(2)), int(mm.group(3))))
                return " %s%d%s " % (MARK, len(found) - 1, MARK)

            marked = ANCHOR_RE.sub(_anchor, body)
            text = WS_RE.sub(" ", TAG_RE.sub(" ", marked)).strip()
            if not text:
                continue

            para_id += 1
            for line_id, raw in enumerate(split_sentences(text), 1):
                # pull any sentinels back out, noting where they sat
                here = []

                def _take(mm):
                    n = int(mm.group(1))
                    prefix = raw[:mm.start()]
                    here.append((n, len(tokenize(prefix, strip_html=False))))
                    return " "

                clean = re.sub(MARK + r"(\d+)" + MARK, _take, raw)
                clean = WS_RE.sub(" ", clean).strip()
                if not clean:
                    continue
                if do_caps:
                    clean = capitalise(clean)
                pages = {}
                for n, offset in here:
                    ed, vol, page = found[n]
                    pages[EDITION_COLUMN[ed]] = "%d.%d" % (vol, page)
                    markers.append((book_id, para_id, line_id, ed, vol, page,
                                    offset, 1))
                sentences.append((
                    book_id, para_id, line_id, None,
                    pages.get("thaipage"), pages.get("vripage"),
                    pages.get("ptspage"), pages.get("mypage"), clean,
                    "verse" if cls.startswith("gatha") else
                    ("continue" if cls == "noindentbodytext" else "paragraph"),
                ))
    return sentences, markers


def main():
    ap = argparse.ArgumentParser(
        description="Convert the TPR books ePitaka does not carry into "
                    "ePitaka-shaped sentences.")
    ap.add_argument("--tpr", required=True, help="path to tipitaka_pali.db")
    ap.add_argument("--out", default="missing_books.db")
    ap.add_argument("--report", default="missing_books_report.txt")
    ap.add_argument("--books", help="comma-separated TPR book ids")
    ap.add_argument("--no-capitalise", dest="caps", action="store_false",
                    help="keep TPR's lower case instead of following ePitaka")
    ap.set_defaults(caps=True)
    args = ap.parse_args()

    if not os.path.exists(args.tpr):
        sys.exit("not found: " + args.tpr)
    books = ([b.strip() for b in args.books.split(",")] if args.books
             else DEFAULT_BOOKS)

    src = sqlite3.connect("file:%s?mode=ro" % args.tpr.replace("\\", "/"), uri=True)
    cur = src.cursor()

    if os.path.exists(args.out):
        os.remove(args.out)
    out = sqlite3.connect(args.out)
    out.executescript("""
        CREATE TABLE sentences (
            book_id TEXT NOT NULL, para_id INTEGER NOT NULL, line_id INTEGER NOT NULL,
            vripara TEXT, thaipage TEXT, vripage TEXT, ptspage TEXT, mypage TEXT,
            pali TEXT, glue_state TEXT,
            PRIMARY KEY (book_id, para_id, line_id)
        );
        CREATE TABLE page_mark (
            book_id TEXT, para_id INTEGER, line_id INTEGER,
            edition TEXT, vol INTEGER, page INTEGER,
            word_index INTEGER, exact INTEGER
        );
    """)

    report = []
    for book_id in books:
        rows = cur.execute(
            "SELECT count(*) FROM pages WHERE bookid=?", (book_id,)).fetchone()[0]
        if not rows:
            report.append("%-20s not present in the source database" % book_id)
            continue
        sents, marks = convert_book(cur, book_id, args.caps)
        out.executemany(
            "INSERT INTO sentences VALUES (?,?,?,?,?,?,?,?,?,?)", sents)
        out.executemany("INSERT INTO page_mark VALUES (?,?,?,?,?,?,?,?)", marks)
        paras = len({(s[1]) for s in sents})
        words = sum(len(tokenize(s[8], strip_html=False)) for s in sents)
        by_ed = {}
        for m in marks:
            by_ed[m[3]] = by_ed.get(m[3], 0) + 1
        report.append(
            "%-20s pages %4d  paragraphs %5d  sentences %6d  words %7d  "
            "M %4d V %4d P %4d T %4d"
            % (book_id, rows, paras, len(sents), words,
               by_ed.get("M", 0), by_ed.get("V", 0),
               by_ed.get("P", 0), by_ed.get("T", 0)))
    out.commit()

    header = [
        "Books converted from TPR because ePitaka does not carry them",
        "capitalisation: %s" % ("following ePitaka" if args.caps else "TPR's own"),
        "every page marker here is exact, since the sentences are built around it",
        "",
    ]
    with open(args.report, "w", encoding="utf-8") as fh:
        fh.write("\n".join(header + report) + "\n")
    print("\n".join(header + report))
    print("wrote %s and %s" % (args.out, args.report))


if __name__ == "__main__":
    main()
