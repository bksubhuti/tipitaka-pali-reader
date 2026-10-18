"""
Builds the extension package that adds ePitaka books TPR has no pages for.

ePitaka carries 67 books TPR cannot open: they have sentences in epitaka.db
but no rows in tpr_extension.db's page_break, so no book in the library, no
pages, no search and no links. Most of them have printed Myanmar page
numbers in VRI's XML (github.com/VipassanaTech/tipitaka-xml, romn/*.xml), and
ePitaka's para_id is the position of the <p> element in that same file, so the
pages can be carried across exactly.

The output is a package database the app installs as it is (see
lib/services/extensions/extension_package.dart): a `meta` table, a `commands`
table of steps to run, and the data those steps copy.

    python build_missing_books.py --epitaka epitaka.db --tpr tipitaka_pali.db \
        --vri path/to/tipitaka-xml/romn --out missing_books.pkg.db [--books Moh,...]

It also writes the zip to publish, missing_books.pkg.zip; the app knows a
package in a zip by the .pkg.db ending.

Every input is opened read-only. Word offsets are counted with the migration's
one tokenizer, tools/epitaka_migration/pali_text.py, as every other page
offset in TPR is.
"""

import argparse
import bisect
import difflib
import os
import re
import sqlite3
import sys
import urllib.request
import zipfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'epitaka_migration'))
from pali_text import tokenize  # noqa: E402

PACKAGE_ID = 'missing_books'
PACKAGE_VERSION = 1

VRI_URL = ('https://raw.githubusercontent.com/VipassanaTech/tipitaka-xml/'
           'main/romn/{}.xml')

# The books this package adds, in library order: ePitaka id, TPR id, basket,
# category, and the name the library shows. The Abhidhamma handbooks first;
# they are core study texts beside the Saṅgaha.
BOOKS = [
    ('Abhidh-av', 'tika_bi_06', 'tika', 'bi', 'abhidhammāvatāro'),
    ('Abhidh-av-pt', 'tika_bi_07', 'tika', 'bi', 'abhidhammāvatāra-purāṇaṭīkā'),
    ('Abhidh-av-nt', 'tika_bi_08', 'tika', 'bi', 'abhidhammāvatāra-abhinavaṭīkā'),
    ('Namar-p', 'tika_bi_09', 'tika', 'bi', 'nāmarūpaparicchedo'),
    ('Abhidh-av-vinich', 'tika_bi_10', 'tika', 'bi', 'paramatthavinicchayo'),
    ('Abhidh-av-sacc', 'tika_bi_11', 'tika', 'bi', 'saccasaṅkhepo'),
    ('AbhMāt', 'tika_bi_12', 'tika', 'bi', 'abhidhammamātikāpāḷi'),
    ('Moh', 'tika_bi_13', 'tika', 'bi', 'mohavicchedanī'),
]

# Sort orders follow the last book of the same kind already in the library.
SORT_AFTER = {('tika', 'bi'): 'tika_bi_05'}

PARA_RE = re.compile(r'<p\b([^>]*)>(.*?)</p>', re.S)
REND_RE = re.compile(r'rend="([^"]*)"')
PB_RE = re.compile(r'<pb ed="([A-Z])" n="(\d+)\.(\d+)"\s*/>')


def read_vri(vri_dir, name):
    """The paragraphs of one VRI file, in order: (rend, body)."""
    path = os.path.join(vri_dir, name + '.xml')
    if not os.path.exists(path):
        os.makedirs(vri_dir, exist_ok=True)
        print('downloading', name)
        urllib.request.urlretrieve(VRI_URL.format(name), path)
    raw = open(path, 'rb').read()
    text = raw.decode('utf-16') if raw[:2] in (b'\xff\xfe', b'\xfe\xff') \
        else raw.decode('utf-8')
    out = []
    for attrs, body in PARA_RE.findall(text):
        m = REND_RE.search(attrs)
        out.append((m.group(1) if m else '', body))
    return out


def markers_in(body):
    """Each page marker in a paragraph: (edition, vol, page, word offset)."""
    out = []
    pos = 0
    words = 0
    for m in PB_RE.finditer(body):
        words += len(tokenize(PB_RE.sub(' ', body[pos:m.start()])))
        pos = m.end()
        out.append((m.group(1), int(m.group(2)), int(m.group(3)), words))
    return out


class Paragraph:
    """One ePitaka paragraph: its sentences' tokens, for placing offsets."""

    def __init__(self, para_id, lines):
        self.para_id = para_id
        self.lines = lines  # [(line_id, tokens)]
        self.words = [w for _, toks in lines for w in toks]

    def place(self, offset):
        """(line_id, word_index) of word [offset] of the paragraph."""
        for line_id, toks in self.lines:
            if offset < len(toks):
                return line_id, offset
            offset -= len(toks)
        line_id, toks = self.lines[-1]
        return line_id, len(toks)


def map_offset(vri_words, epi_words, offset):
    """Where word [offset] of the VRI paragraph falls in ePitaka's, and
    whether it fell inside text the two agree on."""
    if vri_words == epi_words:
        return offset, True
    sm = difflib.SequenceMatcher(None, vri_words, epi_words, autojunk=False)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if offset < i2 or (offset == i2 and tag == 'equal' and i2 == len(vri_words)):
            if tag == 'equal':
                return j1 + (offset - i1), True
            # Inside a stretch the two word differently: the start of the
            # matching stretch, which is a word or two off at most.
            return min(j1 + (offset - i1), max(j2 - 1, j1)), False
    return len(epi_words), offset == len(vri_words)


def build(args):
    epi = sqlite3.connect(f'file:{args.epitaka}?mode=ro', uri=True)
    tpr = sqlite3.connect(f'file:{args.tpr}?mode=ro', uri=True)

    wanted = [b for b in BOOKS if not args.books or b[0] in args.books]
    existing = {r[0] for r in tpr.execute('SELECT id FROM books')}
    for _, tpr_id, *_ in wanted:
        if any(e == tpr_id or e.startswith(tpr_id + '_') for e in existing):
            sys.exit(f'{tpr_id} is already a book in tipitaka_pali.db')

    if os.path.exists(args.out):
        os.remove(args.out)
    out = sqlite3.connect(args.out)
    out.executescript('''
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE commands (
            seq INTEGER PRIMARY KEY,
            phase TEXT NOT NULL DEFAULT 'install',  -- install / remove
            op TEXT NOT NULL,                       -- sql / copy / reindex
            target TEXT,
            arg TEXT
        );
        CREATE TABLE books (id TEXT PRIMARY KEY, basket TEXT, category NUMERIC,
            name TEXT, firstpage INTEGER, lastpage INTEGER, pagecount INTEGER,
            sort_order INTEGER);
        CREATE TABLE paragraphs (book_id TEXT, paragraph_number INTEGER,
            page_number INTEGER);
        CREATE TABLE page_break (book_id TEXT NOT NULL, para_id INTEGER NOT NULL,
            line_id INTEGER NOT NULL, tpr_book TEXT NOT NULL,
            tpr_page INTEGER NOT NULL, word_index INTEGER NOT NULL,
            exact INTEGER NOT NULL);
        CREATE TABLE page_mark (book_id TEXT NOT NULL, para_id INTEGER NOT NULL,
            line_id INTEGER NOT NULL, edition TEXT NOT NULL, vol INTEGER,
            page INTEGER, word_index INTEGER NOT NULL, exact INTEGER NOT NULL);
        CREATE TABLE sentence_ext (book_id TEXT NOT NULL,
            para_id INTEGER NOT NULL, line_id INTEGER NOT NULL,
            mypage_word_index INTEGER, glue_state TEXT,
            PRIMARY KEY (book_id, para_id, line_id));
    ''')

    report = []
    sort_base = {}
    vri_cache = {}
    for n, (book, tpr_id, basket, category, name) in enumerate(wanted):
        vri_id = epi.execute('SELECT vri_id FROM books WHERE book_id = ?',
                             (book,)).fetchone()[0]
        vri_name = vri_id  # e.g. abh06t.nrf, published as abh06t.nrf.xml
        if vri_name not in vri_cache:
            vri_cache[vri_name] = read_vri(args.vri, vri_name)
        vri = vri_cache[vri_name]

        paras = {}
        for para_id, line_id, pali in epi.execute(
                'SELECT para_id, line_id, pali FROM sentences WHERE book_id = ? '
                'ORDER BY para_id, line_id', (book,)):
            paras.setdefault(para_id, []).append(
                (line_id, tokenize(pali or '')))
        order = sorted(paras)
        epi_paras = {p: Paragraph(p, lines) for p, lines in paras.items()}

        # Every paragraph of the file holding ePitaka text, whichever book.
        # ePitaka files a paragraph under a neighbouring book now and then
        # (Namar-p's "Namo tassa" is Saccasaṅkhepa's first sentence), so a
        # book can come in runs with other books' text between them.
        owned = {r[0] for r in epi.execute(
            'SELECT DISTINCT s.para_id FROM sentences s JOIN books b '
            'ON b.book_id = s.book_id WHERE b.vri_id = ?', (vri_id,))}
        owned_sorted = sorted(owned)
        others = sorted(owned - set(epi_paras))

        # Walk the file in order, following the Myanmar page, and place
        # every marker that falls in this book. A marker in a paragraph
        # ePitaka folds into the next (a verse number) goes to the start of
        # the paragraph it was folded into.
        first, last = order[0], order[-1]
        marks = []        # (para, line, word, edition, vol, page, exact)
        breaks = []       # (para, line, word, vol, page, exact); page None = unknown
        current = None    # the Myanmar page the text has reached
        previous = None   # the last paragraph of this book seen
        for i, (rend, body) in enumerate(vri, 1):
            if i > last:
                break
            found = markers_in(body)
            if i in epi_paras:
                target = i
            elif i not in owned:
                k = bisect.bisect_right(owned_sorted, i)
                target = owned_sorted[k] if k < len(owned_sorted) else None
                if target not in epi_paras:
                    target = None
            else:
                target = None
            if target is None:
                for ed, vol, page, _ in found:
                    if ed == 'M':
                        current = (vol, page)
                continue

            para = epi_paras[target]
            k = bisect.bisect_right(others, previous) if previous else 0
            if target != previous and (
                    previous is None or
                    (k < len(others) and others[k] < target)):
                # The book starts, or comes back after another's text.
                line = para.lines[0][0]
                breaks.append((target, line, 0) + (current or (None, None))
                              + (1, True))
            previous = target
            if target == i:
                vri_words = tokenize(PB_RE.sub(' ', body))
                for ed, vol, page, at in found:
                    offset, exact = map_offset(vri_words, para.words, at)
                    line, word = para.place(offset)
                    marks.append((i, line, word, ed, vol, page, int(exact)))
                    if ed == 'M':
                        breaks.append((i, line, word, vol, page, int(exact),
                                       False))
                        current = (vol, page)
            else:
                line = para.lines[0][0]
                for ed, vol, page, _ in found:
                    marks.append((target, line, 0, ed, vol, page,
                                  int(rend == 'hangnum')))
                    if ed == 'M':
                        breaks.append((target, line, 0, vol, page,
                                       int(rend == 'hangnum'), False))
                        current = (vol, page)

        if not any(not b[6] for b in breaks):
            report.append(f'{book}: no Myanmar pages, left out')
            continue
        # Where the book starts, or comes back, it is on the page the text
        # before it reached, but only if the next marker carries that page
        # on (Moh starts part way down page 95 and 96 follows). A book that
        # starts its own numbering, as each book in abh06t does from 1, is
        # on its own first page.
        resolved = []
        for k, b in enumerate(breaks):
            if b[6]:
                nxt = next((c for c in breaks[k + 1:] if not c[6]), None)
                continues = (nxt is not None and b[4] is not None and
                             nxt[3] == b[3] and nxt[4] == b[4] + 1)
                if not continues:
                    if nxt is None:
                        continue
                    b = b[:3] + nxt[3:5] + (1, True)
            resolved.append(b[:6])
        merged = []
        for b in resolved:
            if merged and b[3:5] == merged[-1][3:5]:
                continue
            if merged and b[:3] == merged[-1][:3]:
                # Two pages starting at one place: the later one wins.
                merged[-1] = b
                continue
            merged.append(b)

        # One TPR book per printed volume, as TPR has always split them,
        # so that page numbers are the printed ones.
        volumes = []
        for b in merged:
            if not volumes or volumes[-1][0] != b[3]:
                volumes.append((b[3], []))
            pages = volumes[-1][1]
            if pages and b[4] <= pages[-1][3]:
                report.append(f'{book}: page {b[4]} of volume {b[3]} out of '
                              f'order after {pages[-1][3]}, dropped')
                continue
            pages.append((b[0], b[1], b[2], b[4], b[5]))

        for para, line, word, ed, vol, page, exact in marks:
            out.execute('INSERT INTO page_mark VALUES (?,?,?,?,?,?,?,?)',
                        (book, para, line, ed, vol, page, word, exact))

        # Verse lines break without opening a prose paragraph.
        for i in order:
            rend = vri[i - 1][0] if i <= len(vri) else ''
            if rend.startswith('gatha'):
                out.execute('INSERT OR REPLACE INTO sentence_ext '
                            '(book_id, para_id, line_id, glue_state) '
                            'VALUES (?,?,?,?)',
                            (book, i, epi_paras[i].lines[0][0], 'verse'))

        numerals = ['pa', 'du', 'ta', 'ca', 'pañca']
        key = (basket, category)
        if key not in sort_base:
            after = SORT_AFTER.get(key)
            row = tpr.execute('SELECT sort_order FROM books WHERE id = ?',
                              (after,)).fetchone() if after else None
            sort_base[key] = (row[0] if row else 9000)
        vripara = [(para_id, int(m.group()))
                   for para_id, v in epi.execute(
                       "SELECT para_id, vripara FROM sentences WHERE book_id = ? "
                       "AND vripara <> '' ORDER BY para_id, line_id", (book,))
                   for m in [re.match(r'\d+', v or '')] if m]
        for k, (vol, pages) in enumerate(volumes):
            split = len(volumes) > 1
            vid = f'{tpr_id}_{k + 1:02d}' if split else tpr_id
            vname = f'{name} ({numerals[k]})' if split else name
            for para, line, word, page, exact in pages:
                out.execute('INSERT INTO page_break VALUES (?,?,?,?,?,?,?)',
                            (book, para, line, vid, page, word, exact))

            # Paragraph numbers, for going to a paragraph: the page each
            # first appears on, within this volume.
            first_para = pages[0][0]
            next_para = (volumes[k + 1][1][0][0] if k + 1 < len(volumes)
                         else 1 << 30)
            seen = set()
            for para_id, number in vripara:
                if para_id < first_para or para_id >= next_para or number in seen:
                    continue
                seen.add(number)
                page = pages[0][3]
                for p, _, _, pg, _ in pages:
                    if p <= para_id:
                        page = pg
                    else:
                        break
                out.execute('INSERT INTO paragraphs VALUES (?,?,?)',
                            (vid, number, page))

            sort_base[key] += 1
            out.execute('INSERT INTO books VALUES (?,?,?,?,?,?,?,?)',
                        (vid, basket, category, vname, pages[0][3],
                         pages[-1][3], len(pages), sort_base[key]))
            inexact = sum(1 for b in pages if not b[4])
            report.append(f'{book:18} -> {vid:15} pages {pages[0][3]}-'
                          f'{pages[-1][3]} ({len(pages)}), '
                          f'{inexact} placed inexactly')
        report.append(f'{"":18}    {len(marks)} page marks (M, V, P)')

    books = [r[0] for r in out.execute('SELECT DISTINCT book_id FROM page_break')]
    tpr_ids = [r[0] for r in out.execute('SELECT id FROM books ORDER BY sort_order')]
    in_list = ','.join(f"'{b}'" for b in tpr_ids)
    epi_list = ','.join(f"'{b}'" for b in books)

    out.executemany('INSERT INTO meta VALUES (?,?)', [
        ('id', PACKAGE_ID),
        ('version', str(PACKAGE_VERSION)),
        ('title', 'Books missing from TPR'),
        ('description', 'Adds ePitaka books that had no pages in TPR, '
                        'paged by VRI\'s Myanmar page numbers.'),
        ('format', '1'),
    ])
    # Rows these books own are cleared first, so applying again (after an
    # update replaces the databases, or a newer package) leaves one copy.
    clear = [
        ('sql', None, f'DELETE FROM main.books WHERE id IN ({in_list})'),
        ('sql', None, f'DELETE FROM main.paragraphs WHERE book_id IN ({in_list})'),
        ('sql', None, f'DELETE FROM ext.page_break WHERE tpr_book IN ({in_list})'),
        ('sql', None, f'DELETE FROM ext.page_mark WHERE book_id IN ({epi_list})'),
        ('sql', None, f'DELETE FROM ext.sentence_ext WHERE book_id IN ({epi_list})'),
    ]
    steps = [('install', *c) for c in clear] + [
        ('install', 'copy', 'main.books', 'books'),
        ('install', 'copy', 'main.paragraphs', 'paragraphs'),
        ('install', 'copy', 'ext.page_break', 'page_break'),
        ('install', 'copy', 'ext.page_mark', 'page_mark'),
        ('install', 'copy', 'ext.sentence_ext', 'sentence_ext'),
        ('install', 'reindex', None, ','.join(books)),
    ] + [('remove', *c) for c in clear] + [
        ('remove', 'reindex', None, ','.join(books)),
    ]
    out.executemany('INSERT INTO commands (phase, op, target, arg) '
                    'VALUES (?,?,?,?)', steps)
    out.commit()
    out.execute('VACUUM')
    out.close()

    base = args.out[:-len('.db')] if args.out.endswith('.db') else args.out
    with zipfile.ZipFile(base + '.zip', 'w', zipfile.ZIP_DEFLATED) as z:
        z.write(args.out, os.path.basename(args.out))

    text = '\n'.join(report)
    print(text)
    with open(base + '_report.txt', 'w') as f:
        f.write(text + '\n')


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--epitaka', required=True)
    ap.add_argument('--tpr', required=True, help='tipitaka_pali.db, to avoid id clashes')
    ap.add_argument('--vri', required=True, help='folder of VRI romn/*.xml (downloaded if missing)')
    ap.add_argument('--out', default='missing_books.pkg.db')
    ap.add_argument('--books', type=lambda s: s.split(','), default=None)
    build(ap.parse_args())


if __name__ == '__main__':
    main()
