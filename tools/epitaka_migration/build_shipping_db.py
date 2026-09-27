#!/usr/bin/env python3
"""
Build the ePitaka database TPR ships, keeping only what the app reads.

The published file is 578 MB and carries a great deal TPR has no use for:
Burmese dictionaries, Pali definitions, embedding chunks for a search TPR does
not do, and index after index on all of them. It also keeps four columns of
printed page numbers per sentence, which TPR does not read either, because the
page positions it needs are exact word offsets held in its own table rather
than ePitaka's sentence-level rounding.

What is kept:
    sentences    book, paragraph, line, the VRI paragraph number, the Pali
    headings     the structure behind the table of contents
    book_links   the Mula, Atthakatha and Tika cross-references
    books        names and ordering

Indexes are rebuilt rather than inherited, so only the ones the app's own
queries use are present.

This also means TPR keeps its own copy rather than depending on a rolling
release that can change without notice.
"""

import argparse
import os
import sqlite3
import sys
import time

# Columns TPR reads. Everything else in these tables is dropped.
KEEP = {
    'sentences': ['book_id', 'para_id', 'line_id', 'vripara', 'pali'],
    # sc_id is SuttaCentral's identifier: small, and what sutta shortcuts
    # would be keyed on when they move across, so it is worth its few bytes.
    'headings': ['book_id', 'para_id', 'level', 'title', 'sc_id'],
    'book_links': ['src_book', 'src_para', 'src_line',
                   'dst_book', 'dst_para', 'dst_line'],
    'books': None,  # all of it; 286 rows
}

# Only what the app actually queries by.
INDEXES = [
    'CREATE INDEX idx_sentence ON sentences(book_id, para_id, line_id)',
    'CREATE INDEX idx_heading ON headings(book_id, para_id)',
    'CREATE INDEX idx_link_src ON book_links(src_book, src_para)',
    'CREATE INDEX idx_link_dst ON book_links(dst_book, dst_para)',
]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source', required=True, help='the published epitaka.db')
    ap.add_argument('--out', default='epitaka_ship.db')
    args = ap.parse_args()

    if not os.path.exists(args.source):
        sys.exit('not found: ' + args.source)
    if os.path.exists(args.out):
        os.remove(args.out)

    started = time.time()
    db = sqlite3.connect(args.out)
    db.executescript('PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF;')
    db.execute('ATTACH DATABASE ? AS src', (args.source.replace('\\', '/'),))

    for table, columns in KEEP.items():
        available = [r[1] for r in db.execute(f'PRAGMA src.table_info({table})')]
        wanted = [c for c in (columns or available) if c in available]
        types = {r[1]: r[2] for r in db.execute(f'PRAGMA src.table_info({table})')}
        spec = ', '.join(f'"{c}" {types.get(c, "")}'.strip() for c in wanted)
        db.execute(f'CREATE TABLE "{table}" ({spec})')
        cols = ', '.join(f'"{c}"' for c in wanted)
        db.execute(f'INSERT INTO "{table}" ({cols}) SELECT {cols} FROM src."{table}"')
        dropped = [c for c in available if c not in wanted]
        print(f'  {table:12} {len(wanted)} columns kept'
              + (f', dropped {", ".join(dropped)}' if dropped else ''))

    db.commit()
    db.execute('DETACH DATABASE src')
    for statement in INDEXES:
        db.execute(statement)
    db.commit()
    db.execute('VACUUM')
    db.close()

    print('\n%s: %.0f MB  (from %.0f MB) in %.0fs'
          % (args.out,
             os.path.getsize(args.out) / 1048576,
             os.path.getsize(args.source) / 1048576,
             time.time() - started))


if __name__ == '__main__':
    main()
