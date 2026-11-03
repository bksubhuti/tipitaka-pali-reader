#!/usr/bin/env python3
"""Build the chanting books as extension packages, one per book.

Each book was an old `.sql` extension: rows for `books`, `category`, `pages`
and `tocs`, the pages HTML with Pāḷi and English lines side by side and
nothing to tell them apart but class names that differ from book to book.
Here every line is marked as the ePitaka pages mark theirs: Pāḷi in
`<span class="palitext">`, English in `<span class="translation_text"
lang="en">`. So the reader treats the English as a translation (its font,
colour, the Pāḷi / translation display modes) and converts only the Pāḷi to
the reader's script. The Pāḷi's ṁ is written ṃ, which the script converters
expect.

The book ids stay as they were, so bookmarks and history still open them.

    python3 build_chanting_books.py <folder with the old .sql files> <out folder>

Each book becomes <id>.pkg.db and <id>.pkg.zip in the out folder; a report of
the lines marked each way, and of those it could not tell, is printed.
"""

import html
import re
import sqlite3
import sys
import zipfile
from pathlib import Path

PACKAGE_FORMAT = 1
PACKAGE_VERSION = 1

# package id -> (old .sql file name, title shown in the library)
BOOKS = {
    "chant_daily": ("Daily_Chanting.sql", "Daily Chanting"),
    "chant_meditators": ("Chanting_for_Meditators.sql", "Chanting for Meditators"),
    "chant_safeguards": ("Safeguard-Recitals.sql", "Safeguard Recitals"),
    "chant_iit": ("iit_chantingbook.sql", "IIT Chants"),
    "chant_sbs": ("sbs_pali_recitation.sql", "SBS Chants"),
}

# Words that mark a line as English. Words Pāḷi also has (so, me, no, te,
# ca, na, ti) are left out.
ENGLISH = set(
    """the to of and in is i you he she it we they may all be this that with
    for who which by on as are was were my his her our your their not from at
    or there these those have has had will shall let us one an into upon
    when what whose whom where through every do does did been being
    am its them him over under than then thus also only even such each
    should would could can might must own very more most other some any
    good well being beings life mind body peace happy free from without
    within out up down after before until while like just here now
    homage worthy blessed fully perfectly enlightened teaching community
    refuge go going gone take taking undertake precept precepts abstain
    from killing stealing lying recite recitation chant chanting verse
    verses text introductory safeguard protection meditation recollection
    loving kindness death loathsomeness first second third times""".split()
)

PALI_LETTERS = set("āīūṃṁñṅṭḍṇḷĀĪŪṂṀÑṄṬḌṆḶ")
WORD = re.compile(r"[A-Za-zāīūṃṁñṅṭḍṇḷĀĪŪṂṀÑṄṬḌṆḶ']+")


def _english_words() -> set[str]:
    """The system word list, for lines of one word with no English cue."""
    try:
        return {w.strip().lower() for w in open("/usr/share/dict/words")}
    except OSError:
        return set()


DICTIONARY = _english_words()


def in_dictionary(w: str) -> bool:
    """An English word, or a plural or -ed / -ing form of one."""
    return (w in DICTIONARY or (w.endswith("s") and w[:-1] in DICTIONARY)
            or (w.endswith("es") and w[:-2] in DICTIONARY)
            or (w.endswith("ed") and (w[:-2] in DICTIONARY or w[:-1] in DICTIONARY))
            or (w.endswith("ing") and w[:-3] in DICTIONARY))
MARKER = re.compile(r"^\s*[\[(][^\])]{0,20}[\])]\s*[.,;:]?\s*$")


def language(text: str) -> str | None:
    """'pi', 'en', or None for a marker such as [1], (3x) or [DN 21]."""
    words = [w.lower().strip("'") for w in WORD.findall(text)]
    words = [w for w in words if len(w) > 1 or w == "i"]
    if not words:
        return None
    if MARKER.match(text) and len(words) <= 2:
        # an instruction such as (lights) is English; [DN 21] or (3x) is not
        if any(ch in PALI_LETTERS for ch in text):
            return "pi"
        if all(in_dictionary(w) and w not in ("dn", "sn", "mn", "an") for w in words):
            return "en"
        return None
    english = sum(w in ENGLISH for w in words)
    pali_letters = any(ch in PALI_LETTERS for ch in text)
    if english:
        share = english / len(words)
        if share >= 0.2 or (not pali_letters and share >= 0.1):
            return "en"
        return "pi"
    if pali_letters:
        return "pi"
    # no cue either way: English when every word is an English word
    if all(in_dictionary(w) for w in words):
        return "en"
    return "pi"


def wrap(inner: str, lang: str | None) -> str:
    if lang == "pi":
        return f'<span class="palitext">{inner.replace("ṁ", "ṃ").replace("Ṁ", "Ṃ")}</span>'
    if lang == "en":
        return f'<span class="translation_text" lang="en">{inner}</span>'
    return inner


BLOCK = re.compile(r"(<(p|h[1-6])(\s[^>]*)?>)(.*?)(</\2>)", re.S)
SPAN = re.compile(r'(<span class="t\d+">)(.*?)(</span>)', re.S)
TAGS = re.compile(r"<[^>]+>")
NESTED = re.compile(r"<span[^>]*>[^<]*<span")
TITLE = re.compile(r"^(?P<num>\s*[\d.]*\s*)(?P<pali>[^<>()]+?)\s*\((?P<en>[^<>()]+)\)(?P<end>[\s:.]*)$")


def plain(fragment: str) -> str:
    return html.unescape(TAGS.sub(" ", fragment))


def mark_page(content: str, stats: dict, unsure: list) -> str:
    def one_block(m: re.Match) -> str:
        open_tag, _, _, inner, close_tag = m.groups()
        # "12. Saṅgha-vandanā (Homage to the Sangha):" is a Pāḷi title with
        # its English in brackets: each part is marked on its own.
        both = TITLE.match(inner)
        if both and language(both["pali"]) == "pi" and language(both["en"]) == "en":
            count("pi", both["pali"])
            count("en", both["en"])
            return (open_tag + both["num"] + wrap(both["pali"], "pi") + " ("
                    + wrap(both["en"], "en") + ")" + both["end"] + close_tag)
        whole = language(plain(inner))
        # A block is nearly always one line, marked as a whole. Only spans
        # side by side, not nested, of which some are clearly Pāḷi and some
        # clearly English, are marked one by one.
        spans = SPAN.findall(inner)
        if (len(spans) > 1 and not NESTED.search(inner)
                and not plain(SPAN.sub("", inner)).strip()):
            sure = {language(plain(b)) for _, b, _ in spans
                    if len(WORD.findall(plain(b))) >= 3}
            if {"pi", "en"} <= sure:
                parts = []
                for so, body, sc in spans:
                    lang = language(plain(body)) or whole
                    count(lang, plain(body))
                    parts.append(f"{so}{wrap(body, lang)}{sc}")
                return open_tag + "".join(parts) + close_tag
        count(whole, plain(inner))
        return open_tag + wrap(inner, whole) + close_tag

    def count(lang, text):
        stats[lang] = stats.get(lang, 0) + 1
        if lang is None and WORD.search(text) and len(unsure) < 400:
            unsure.append(text.strip()[:80])

    return BLOCK.sub(one_block, content)


SCHEMA = {
    "books": """("id" TEXT, "basket" TEXT, "category" NUMERIC, "name" TEXT,
        "firstpage" INTEGER, "lastpage" INTEGER, "pagecount" INTEGER,
        "sort_order" INTEGER DEFAULT 0, PRIMARY KEY("id"))""",
    "category": """("id" TEXT, "name" TEXT, "basket" TEXT,
        "sort_order" INTEGER DEFAULT 0, PRIMARY KEY("id"))""",
    "pages": """("id" INTEGER NOT NULL, "bookid" TEXT, "page" INTEGER,
        "content" TEXT, "paranum" TEXT, PRIMARY KEY("id" AUTOINCREMENT))""",
    "tocs": """("book_id" TEXT, "name" TEXT, "type" TEXT, "page_number" INTEGER)""",
}


def flat(sql: str) -> str:
    return " ".join(sql.split())


def load_old(sql_file: Path) -> sqlite3.Connection:
    """The old extension, run into an empty database of the same tables."""
    db = sqlite3.connect(":memory:")
    for table, columns in SCHEMA.items():
        db.execute(f"CREATE TABLE {table} {columns}")
    # The old extensions also cleared the old search index; not carried here.
    db.execute("CREATE TABLE fts_pages (bookid TEXT)")
    db.executescript(sql_file.read_text(encoding="utf-8"))
    return db


def build(pkg_id: str, sql_file: Path, title: str, out: Path) -> dict:
    old = load_old(sql_file)
    (book_id,) = old.execute("SELECT id FROM books").fetchone()
    stats: dict = {}
    unsure: list = []

    path = out / f"{pkg_id}.pkg.db"
    path.unlink(missing_ok=True)
    db = sqlite3.connect(path)
    db.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)")
    db.executemany(
        "INSERT INTO meta VALUES (?, ?)",
        [
            ("id", pkg_id),
            ("version", str(PACKAGE_VERSION)),
            ("title", title),
            ("description", f"{title}, Pāḷi with English"),
            ("format", str(PACKAGE_FORMAT)),
        ],
    )
    db.execute(
        "CREATE TABLE commands (seq INTEGER PRIMARY KEY, "
        "phase TEXT NOT NULL DEFAULT 'install', op TEXT NOT NULL, target TEXT, arg TEXT)"
    )
    # The page rows carry no id: the device's table numbers them.
    db.execute(
        'CREATE TABLE pages ("bookid" TEXT, "page" INTEGER, "content" TEXT, "paranum" TEXT)'
    )
    for table in ("books", "category", "tocs"):
        db.execute(f"CREATE TABLE {table} {SCHEMA[table]}")

    for row in old.execute("SELECT id, basket, category, name, firstpage, lastpage, pagecount FROM books"):
        db.execute("INSERT INTO books VALUES (?,?,?,?,?,?,?,0)", (*row[:3], title, *row[4:]))
    for row in old.execute("SELECT id, name, basket FROM category"):
        db.execute("INSERT INTO category VALUES (?,?,?,0)", row)
    for page, content, paranum in old.execute(
        "SELECT page, content, paranum FROM pages ORDER BY page"
    ):
        db.execute(
            "INSERT INTO pages VALUES (?,?,?,?)",
            (book_id, page, mark_page(content, stats, unsure), paranum),
        )
    db.executemany(
        "INSERT INTO tocs VALUES (?,?,?,?)",
        old.execute("SELECT book_id, name, type, page_number FROM tocs"),
    )

    owned = [
        f"DELETE FROM main.pages WHERE bookid = '{book_id}'",
        f"DELETE FROM main.tocs WHERE book_id = '{book_id}'",
        f"DELETE FROM main.books WHERE id = '{book_id}'",
    ]
    steps = [("install", "sql", None, f"CREATE TABLE IF NOT EXISTS main.{t} {flat(c)}")
             for t, c in SCHEMA.items()]
    steps += [("install", "sql", None, s) for s in owned]
    steps += [("install", "copy", f"main.{t}", t) for t in ("category", "books", "pages", "tocs")]
    steps += [("remove", "sql", None, s) for s in owned]
    db.executemany("INSERT INTO commands (phase, op, target, arg) VALUES (?,?,?,?)", steps)
    db.commit()
    db.execute("VACUUM")
    db.close()

    zip_path = out / f"{pkg_id}.pkg.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        z.write(path, path.name)
    return {"id": pkg_id, "book": book_id, "pali": stats.get("pi", 0),
            "english": stats.get("en", 0), "other": stats.get(None, 0),
            "zip": zip_path, "unsure": unsure}


def main() -> None:
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    for pkg_id, (file_name, title) in BOOKS.items():
        found = list(src.rglob(file_name))
        if not found:
            print(f"{pkg_id}: {file_name} not found")
            continue
        r = build(pkg_id, found[0], title, out)
        print(f"{r['id']:<17} {r['book']:<24} Pāḷi {r['pali']:5}  English {r['english']:5}  "
              f"left {r['other']:4}  {r['zip'].stat().st_size / 1000:.0f} KB")
        for line in r["unsure"][:6]:
            print(f"      left as is: {line}")


if __name__ == "__main__":
    main()
