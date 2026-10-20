#!/usr/bin/env python3
"""List ePitaka books that TPR cannot show: books in epitaka.db with no
page_break rows in tpr_extension.db (so no TPR book, no pages, no search
units, no share links). Read-only.

Usage: check_missing.py [DATA_DIR] [--csv OUT.csv]
DATA_DIR defaults to the macOS app container; it must hold epitaka.db,
tpr_extension.db and tipitaka_pali.db.
"""
import csv
import os
import sqlite3
import sys

DEFAULT = os.path.expanduser(
    "~/Library/Containers/org.americanmonk.tpp/Data/Library/Application Support/org.americanmonk.tpp")


def ro(path):
    return "file:" + path + "?mode=ro"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    out = sys.argv[sys.argv.index("--csv") + 1] if "--csv" in sys.argv else None
    if out in args:
        args.remove(out)
    d = args[0] if args else DEFAULT
    con = sqlite3.connect(ro(os.path.join(d, "epitaka.db")), uri=True)
    con.execute("ATTACH ? AS ext", (ro(os.path.join(d, "tpr_extension.db")),))
    con.execute("ATTACH ? AS tpr", (ro(os.path.join(d, "tipitaka_pali.db")),))
    rows = con.execute("""
        SELECT b.book_id, b.category, b.nikaya, b.book_name, b.vri_id,
               (SELECT count(*) FROM sentences s WHERE s.book_id = b.book_id) AS sentences,
               (SELECT count(*) FROM headings h WHERE h.book_id = b.book_id) AS headings
        FROM books b
        WHERE b.book_id NOT IN (SELECT DISTINCT book_id FROM ext.page_break)
        ORDER BY b.id""").fetchall()
    units = {r[0] for r in con.execute("SELECT DISTINCT epi_book FROM tpr.search_unit")}
    total = con.execute("SELECT count(*) FROM sentences").fetchone()[0]
    missing = sum(r[5] for r in rows)
    by_cat = {}
    for r in rows:
        by_cat.setdefault(r[1], [0, 0])
        by_cat[r[1]][0] += 1
        by_cat[r[1]][1] += r[5]
    print(f"{len(rows)} ePitaka books have no TPR pages "
          f"({missing:,} of {total:,} sentences, {missing / total:.1%})")
    for cat, (n, s) in sorted(by_cat.items()):
        print(f"  {cat:11} {n:3} books {s:8,} sentences")
    stray = [r[0] for r in rows if r[0] in units]
    if stray:
        print("Unexpected: these have search units but no page_break rows:", ", ".join(stray))
    print()
    for r in rows:
        print(f"{r[0]:18} {r[1]:11} {r[5]:6} sent {r[6]:4} hdg  {r[4] or '-':12} {r[3]}")
    if out:
        with open(out, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["book_id", "category", "nikaya", "book_name", "vri_id", "sentences", "headings"])
            w.writerows(rows)
        print(f"\nwrote {out}")


if __name__ == "__main__":
    main()
