---
name: epitaka-missing-books
description: Work on the 67 ePitaka books that TPR cannot display (Mohavicchedanī, Abhidhammāvatāra and its ṭīkās, Nāmarūpapariccheda, Jātaka-ṭīkā, Mahāvaṃsa, the Saṅgāyana puccha-vissajjanā, etc.). They are in epitaka.db but have no TPR book, pages, search units or share links. Use when the user asks about books missing from TPR, adding ePitaka-only books to the reader, the page_break / tpr_extension.db pipeline for new books, or re-checking the gap.
---

# ePitaka books missing from TPR

## The problem

TPR's reader shows books through `tpr_extension.db.page_break`, which maps
(ePitaka `book_id`, para, line, word) → (TPR `tpr_book`, `tpr_page`).
`tools/epitaka_migration` (issue #321) built that map in one direction only,
**TPR book → ePitaka book**: 176 of 179 TPR books were matched, and 3 were
converted from TPR's own text into `extra_sentence`. It never asked the reverse
question. As a result:

- **67 of 286 ePitaka books had no `page_break` rows** (59 since the Abhidhamma handbooks package). That is 172,764 of
  1,283,680 sentences (13.5%): 14 Ṭīkā books (88,785 sentences) and 53 Añña
  books (83,979). Run `scripts/check_missing.py` for the current figures.
- For each of these books there is no entry in the book list, no pages, no
  search units (`search_unit` / `fts_unit`), no TPR share links, and no
  translations shown. The sentences, their `headings` and any `lang_*.db`
  translations are already in `epitaka.db`, keyed by ePitaka ids, and unused.
- **How it was found:** a research quote from the Mohavicchedanī (para 1546)
  had no TPR link, and the book could not be found anywhere in the UI.

### Priority

1. **Abhidhamma handbooks** (Ṭīkā, VRI `abh06t` / `abh08t` / `abh09t`):
   Abhidhammāvatāra (`Abhidh-av`), its purāṇa- and abhinava-ṭīkā
   (`Abhidh-av-pt`, `Abhidh-av-nt`), Nāmarūpapariccheda (`Namar-p`),
   Paramatthavinicchaya (`Abhidh-av-vinich`), Saccasaṅkhepa (`Abhidh-av-sacc`),
   Abhidhammamātikāpāḷi (`AbhMāt`) and Mohavicchedanī (`Moh`). These are core
   study texts beside the Saṅgaha.
2. **Jātaka-ṭīkā**, 5 volumes (`Ja-ṭ-i` … `Ja-ṭ-v`), 57,345 sentences. The
   largest single gap.
3. **Visuddhimagga-nidānakathā** (`Vism-nid`); the **Saṅgāyana
   puccha-vissajjanā** (`DN-pv`, `MN-pv`, `SN-pv`, `AN-pv`, `Vin-pv`, `Abh-pv`,
   `Att-pv`).
4. **Other Añña**: vaṃsa (`Mhv`, `Sas`, `Dat.h`, `Thup`, `Dhātv`, `Jinvdīp` …),
   Anudīpanī, Paṭṭhānuddesadīpanī, nīti texts, grammar (`MoggVutt`, `Padsādh` …),
   devotional works.

For the full list (book_id, layer, nikāya, name, VRI file, sentences,
headings), run `scripts/check_missing.py --csv out.csv`; it reflects what is
installed now.

## Status (2026-10-18)

- **Pages come from VRI, not made up.** VRI's master repo is
  github.com/VipassanaTech/tipitaka-xml (`romn/<vri_id>.xml`, UTF-16). 30 of
  the 53 source files have Myanmar (`M`) page markers, and abh06t also has
  PTS (`P`). The `e12xx` files (MoggVutt, Thūpavaṃsa, Dāṭhāvaṃsa,
  Jinavaṃsadīpanī …) have `ed="O"`. e0605–e0608 and e0701 have none, and
  the Jātaka-ṭīkā is not in VRI at all.
- **ePitaka `para_id` = position of the `<p>` in the VRI file.** Verse
  numbers (`rend="hangnum"`) are folded into the next paragraph.
  Several books share one file, and each restarts its page numbering at 1.
- **Delivered as an extension package**, not as a new shipped database:
  `tools/extension_packages/build_missing_books.py` builds
  `missing_books.pkg.db` (see that folder's README for the format).
  The 8 Abhidhamma handbooks are done as `tika_bi_06` … `tika_bi_13`, with
  Abhidh-av-nt split as `tika_bi_08_01` / `_02`. All 1,801 breaks have been
  checked against VRI. To add more books, extend `BOOKS` and raise
  `PACKAGE_VERSION`.
- **Since DB version 62 (2026-10-20) the package is baked into the shipped
  databases**, not shipped as a package: its install steps are applied to
  `tipitaka_pali.db` and `tpr_extension.db` before splitting (see
  `assets/database/read.md`). The app ships no packages; the package was
  never in a released app (3.0.4+128 predates it). New books go into the
  shipped databases the same way, at the next database release.
- ePitaka files 14 boundary paragraphs under the wrong book (for example
  Namar-p's "Namo tassa", para 4804, is under Abhidh-av-sacc). Reported as
  dhammanana/epitaka_app#39. The builder copes: a book can come in runs.

## Re-check the gap

```bash
python3 .claude/skills/epitaka-missing-books/scripts/check_missing.py [DATA_DIR] [--csv out.csv]
```

DATA_DIR is the folder that holds `epitaka.db`, `tpr_extension.db` and
`tipitaka_pali.db` (default: the macOS app container). Every file is opened
read-only.

## What a book needs before TPR can show it

Read `lib/services/repositories/sentence_page_content_repo.dart` and
`tools/epitaka_migration/README.md` first. For one ePitaka-only book:

| Piece | Where | Notes |
| --- | --- | --- |
| A TPR book id and `books` row | `tipitaka_pali.db.books` (+ category/folder tree for the library UI) | Follow the naming scheme (`tika_bi_06`, `annya_bi_08`, …); check that no id collides |
| Pagination | `tpr_extension.db.page_break` | No Myanmar print pages exist for these books. Either synthesize pages (≈ one TPR page, about 200 words, breaking only between sentences) or take page anchors from the VRI CSCD source (`abh06t.nrf` etc.) if it has them. Mark synthesized breaks `exact = 0` |
| Page markers (optional) | `page_mark` | Only if VRI/PTS/Thai positions are available |
| Table of contents | `tocs`, `paragraphs` | Built from `epitaka.db.headings` (e.g. `Moh` has 108 headings, `Namar-p` 1,887) |
| Search | `search_unit`, `fts_unit`, `fts_translation_unit` | Re-run `build_fts.py`, or the in-app `sentence_fts_builder.dart`, once `page_break` exists. `page_map` is computed from `page_break` |
| Translations | nothing to do | `lang_*.db` are keyed by ePitaka ids and appear once pages exist |
| Share links | nothing to do | Deep links use `book_id` + `page_number` from the new rows |

## Cautions

- **One tokenizer.** Count words with `tools/epitaka_migration/pali_text.py`,
  as the README warns. TPR's index builder turns each tag into a space before
  counting, and `page_map` offsets are word counts measured that way. A
  different count moves page breaks by a word or two without any error.
- **Never modify `epitaka.db`.** Use it exactly as downloaded; new data goes in
  `tpr_extension.db` and `tipitaka_pali.db`.
- **Bump the versions** (`epitaka.db.version`, `tpr_extension.db.version`, and
  the search `format` in `search_meta`) so existing installs rebuild their
  index.
- **Write a report** like the existing ones (`*_report.txt`): pages per book,
  sentences, any sentence that fell outside a page.

## Done when

- `check_missing.py` reports 0 books (or only books deliberately left out,
  listed with the reason).
- Each new book opens in TPR, pages forward and back, shows its TOC and English,
  and is found by a Pali and an English search.
- A share link to a mid-book page opens on the right page with the passage
  marked. Test `Moh` para 1546:4 (*kiñcāpi khīṇāsavānaṃ upādānakkhandhā*).

## Related gap (separate fix)

`tools/epitaka_migration/book_map_report.txt` also lists **mapped** books with
weak coverage. Text there may lack page rows even though the book exists:
`annya_sadda_12` → `Abh-ṭ` 38.4%, `attha_an_04` → `Mp-viii…xi` 61.2%,
`annya_vi_09` → `Kkh-pt`/`Kkh-nt` 61.6%, `annya_sadda_01` 69.2%,
`annya_sadda_15` 71.4%, `annya_vi_10` 73.0%, `tika_vi_03` 77.2%.
Check whether those uncovered ranges can be reached in the reader.
