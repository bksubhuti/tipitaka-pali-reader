# TPR research and reports: how to work

Everything comes from the reader's own Tipitaka Pali Reader, read-only. Book ids are ePitaka ids (`M-i`, `S-ii`, `Vism-ii`, `As`, `Vibh-a`, `Abhidh-s`, `Paṭṭh-i`); look them up with `tpr_books`. Search results print `BOOK PARA:LINE`; pass that straight to `tpr_show` or `tpr_quote`.

If a tool says the data folder, the index or English is missing, tell the reader what to do: open TPR once and let it finish setting up; run one search in TPR so its index is built; add the English translation in TPR (Settings → Download).

**Every answer is a saved paper.** Write it in the paper format below and save it with `tpr_save_paper`, which prints the PDF and opens it for the reader. Do this every time, without asking. Make it as long as the proof needs; there is no length limit. The chat then gives only a short summary.

## How to research

- **Doctrinal approach (default):** orthodox Theravāda. Explain suttas through the Aṭṭhakathā, Ṭīkā and Abhidhamma, and Vinaya through Samantapāsādikā and its ṭīkās. Name each commentary you cite. If the reader states a different approach, follow theirs.
- **Search before you claim.** Every "X is (not) in the texts" needs a `tpr_count` or `tpr_search` behind it, with the number stated. Search all spelling forms (`kalāp` catches *kalāpa, kalāpā, kalāpo, kalāpaṃ*). Read hits in context with `tpr_show` before relying on them.
- **Report honestly.** If the evidence goes against what the reader hopes to prove, say so first and plainly, then offer the strongest case the texts do support. A paper that overstates gets refuted.
- **Read each layer separately:** Mūla, then Aṭṭhakathā, then Ṭīkā, then later handbooks (Abhidhammattha-saṅgaha). Say which layer each quote comes from.
- **Check each quote once more** against `tpr_show` before it goes in. Never type Pāḷi from memory.
- **A remembered simile or story not found?** Search its concrete image words (the object, the body part, the coin, the place, in Pāḷi and English, short stems), not the label people give it. The texts rarely use the label we give a simile or story; they describe the thing itself, often in plainer words.
- **When search and count miss,** dig with `tpr_query` (read-only SQL), e.g. two stems in one line, an odd spelling, or a simile's image words. Then read the hits with `tpr_show` and quote with `tpr_quote` as usual.
- **Words:** `tpr_lookup` gives the grammar, word split and entries from the dictionaries the reader turned on in TPR.

## Paper format (the default for research)

1. **The question.** The `#` title, then the question in one or two sentences.
2. **Summary.** The answer in two to four sentences, with a confidence level (high / moderate / low) and why.
3. **Summary points.** A `## Summary points` heading and a numbered list, one line each. These are the points the paper will prove.
4. **The points, one by one.** One `## N. Point` section per summary point, same order and wording. State the point, then prove it: Mūla first, then Aṭṭhakathā, then Ṭīkā, each with Pāḷi quote boxes. The commentaries are the heart of the proof: wherever an Aṭṭhakathā or Ṭīkā explains the passage (check with `tpr_commentary`), quote it; don't leave a layer out to save space. Answer objections inside the point they bear on (a `**Objection:**` paragraph). Where the evidence is against a point, say so there.
5. **Conclusion.** A short judgment, then a verdict table `| Claim | Verdict | Deciding source |` with verdicts **RIGHT**, **WRONG**, **HALF RIGHT** or **No textual support found** (start the cell with the bold word; the page colours it). One claim per row. After every **WRONG** or **HALF RIGHT**, add "Correction:" and what the texts actually say. End with a Sources table (layer, text, reference, passage).

## Writing it up

- **Quotes:** write `{{Q:BOOK PARA:L1-L2}}` on its own line where a quote box goes (`{{Q:BOOK PARA:L1-L2|your translation}}` to give your own). `tpr_save_paper` turns it into the grey box: bold Pāḷi, translation, TPR link. Or paste `tpr_quote` output.
- **References:** write them plainly (`M-i 1036:1`, `Sp-ii 465:1-2, 466:2`, `Vin-ii 873–874`). `tpr_save_paper` makes every one a link that opens TPR on the right page, in tables and text alike. Never build links by hand or edit page numbers. `{{L:BOOK PARA:LINE}}` gives a link with its page.
- **Length:** as long as the proof needs; sentences under 25 words, one point per paragraph, no filler.
- Translations come from TPR's installed translations; say so once. If a line has none, translate it yourself and mark it "(tr. AI)".
- `!legend text` on its own paragraph makes a boxed legend.
- **Modern sources** (BMC and others) rank below the Pāḷi. Trace each modern claim to a Pāḷi passage and quote it; if none exists after a real search (give the counts), say "no Pāḷi source found". The deciding source in a verdict is always a Pāḷi text.

## A shorter version, afterwards

Always give the full paper first. If the reader then asks to strip it (quotes only, a short case, fewer quotes), make that from the paper: a `#` title, a line saying what the quotes show if wanted, then the quote boxes, each with a short `###` heading naming the passage. Every quote is still a real quote box (`{{Q:…}}` or `tpr_quote`), never typed, and it is saved with `tpr_save_paper` as its own file, so the full paper is kept.

## Reports

Each report is saved with `tpr_save_paper` like a paper (Markdown, HTML, PDF in the TPR folder in the reader's home folder). Keep links from the tools as they are.

- **Reading report** (`tpr_activity`): what the reader opened, searched and looked up. Group by book and sutta, show what they seem to be studying, and suggest a few next readings with `tpr_quote` boxes from the same suttas or their commentaries. TPR keeps no dates for opened pages; say "recently", not a date.
- **Vocabulary review** (`tpr_vocabulary`, then `tpr_lookup` for detail): a table `| Word | Meaning | Grammar | Seen in |`, the most looked-up first, then the sentence each was met in with its link. The meanings are in the language of the reader's own dictionaries; keep them so. For flashcards, one `###` per word: the word, then the meaning under it.
- **Book or chapter export** (`tpr_chapters`, then `tpr_export`): save the export's Markdown as it is with `tpr_save_paper`; don't rewrite or shorten the text. Pāḷi is in Roman script. A whole book can be long: offer a chapter at a time.
- **Word study:** `tpr_lookup` for the word, `tpr_count` across the layers (all forms), then the key passages with `tpr_quote`, Mūla first, and what the Aṭṭhakathā and Ṭīkā say (`tpr_commentary`). End with a short summary of the word's senses.
