# TPR to ePitaka migration tooling

Build tooling for [tipitaka-pali-reader#321](https://github.com/bksubhuti/tipitaka-pali-reader/issues/321):
moving TPR from its page-based `pages` table to ePitaka's sentence-based format
while keeping the printed page numbers and the original paragraphing.

Nothing here modifies either source database. Both are opened read-only, and
`epitaka.db` is used exactly as downloaded.

## What this produces

`tpr_extension.db`, a small database the app reads alongside `epitaka.db`,
keyed the same way ePitaka keys its sentences:

| table | what it holds |
| --- | --- |
| `sentence_ext` | the Myanmar page offset and the glue state, one row per sentence that has something to say |
| `page_mark` | every printed page position, all four editions, with an exactness flag |
| `extra_sentence` | the three books ePitaka does not carry, converted from TPR |

If ePitaka later adopts these fields into its own sentence table, the reader
selects them from there and this file goes away.

## The pipeline

Run in order. Each step writes a report meant to be read, not just counted.

```bash
python extract_original.py --source /path/to/tipitaka_pali.db
python map_books.py       --tpr /path/to/tipitaka_pali.db --epitaka epitaka.db
python match_markers.py   --tpr /path/to/tipitaka_pali.db --epitaka epitaka.db
python convert_missing_books.py --tpr /path/to/tipitaka_pali.db
python build_extension.py
python build_fts.py --epitaka epitaka.db --tpr /path/to/tipitaka_pali.db
```

1. **extract_original.py** reads the printed page positions out of the original
   pages. They are already there, as inline anchors (`<a name="M1.0002">`) sitting
   at the exact word, for Myanmar, VRI, PTS and Thai. No junction guessing is
   needed. Paragraph structure is recorded in the same pass.
2. **map_books.py** works out which ePitaka book holds each TPR book's text, by
   content rather than by a hand-kept table. Counting shared phrases does not
   work, because the canon's stock formulas recur everywhere; the choice is made
   on positional continuity instead.
3. **match_markers.py** aligns the two word streams per book and carries every
   marker and paragraph break across.
4. **convert_missing_books.py** builds ePitaka-shaped sentences for the three
   books ePitaka lacks, from TPR's own VRI text.
5. **build_extension.py** assembles the deliverable.
6. **build_fts.py** builds the search units and measures what the change buys.

## Search units

A unit is a run of whole paragraphs of about page size, and consecutive units
overlap by one paragraph. Sentence-sized units would break phrase search;
paragraph-sized units would shorten the reach of distance search, a paragraph
being about 40 words against a page's 200. Unit boundaries never fall inside a
sentence, and nothing falls between two units.

## One thing to be careful about

Every step must count words with the same tokenizer, which is why there is
exactly one, in `pali_text.py`. An offset counted one way and looked up another
moves page markers by a word or two, and no summary number reveals it: during
development the alignment and exact-match percentages both stayed healthy while
the offsets were quietly wrong. The check that catches it is comparing a stored
context fingerprint against the word stream at its stored offset.

Two specifics that matter for Pali here: punctuation has to separate words
rather than be deleted from them, or the peyyala ellipsis merges into its
neighbours; and anchors are carried through tokenization as sentinel tokens
spelled with `q` and `x`, letters romanized Pali does not use.
