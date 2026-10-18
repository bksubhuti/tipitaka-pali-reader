# Tipitaka Pali Reader

## Getting the databases

The databases are too big for git. Download them from the GitHub release
[`sentence-data-2026-09-28`](https://github.com/bksubhuti/tipitaka-pali-reader/releases/tag/sentence-data-2026-09-28)
into `assets/database/`:

| file | what it is |
| --- | --- |
| `tipitaka_pali.db.tar.bz2` | the main database: dictionaries, word lists, contents, user tables |
| `epitaka_part.aa` … `epitaka_part.ad` | ePitaka's sentences, headings and links, where the text comes from |
| `tpr_extension_part.aa` | TPR's page breaks and page markers for those sentences |

Then unpack and split the main database:

```
cd assets/database
tar -xjf tipitaka_pali.db.tar.bz2 && rm tipitaka_pali.db.tar.bz2
./split.sh
sha256sum -c SHA256SUMS      # on macOS: shasum -a 256 -c SHA256SUMS
```

The parts on disk must be exactly those listed in `pubspec.yaml`, and the
hashes must match `SHA256SUMS`. Do not leave the `.tar.bz2` or the joined
`.db` in the folder when building a release: everything there is bundled.
`assets/database/read.md` explains how each database is built.

Books added since that release come as extension packages in
`assets/packages/`, which are in git, so there is nothing to download for
them. See `tools/extension_packages/README.md`.

A new Flutter project forked from Tipitaka Pali

Functional requirements.
https://docs.google.com/document/d/1gQ5B16EjiGMyDUy9S6viJaBv-vZqiZpggkDQHn3z4kc/edit#heading=h.7yusba36e4f6

Function Requirements Document (FRC)



# New Road Map
* 1.)  ~~Dictionary History and management items~~
* 2.)  ~~Search History and management of items~~
* 3.)  Change management of recent and notes to be multiselect and more standard
* 4.)  FIrebase for personal settings (recent, dictionary, search, and notes history
* 5.)  ~~Fuzzy search (need to improve search like TPP)  switch to ignore and find all combinations of diacritical marks.  samanera will find the right word (sāmaṇera)~~
* 6.)  Fuzzy Dictionary lookup  samanera will find (sāmaṇera)
* 7.)  ~~Quick jump~~
* 8.)  ~~Right click word "To search"~~
* 9.)  Include 2 or 3 dpd features (Grammar DPD is comming as well as word family and compounds)
* 10.) use expanded widgets with html for dictionary instead of raw html
* 11.)  ~~Import the MAT tables and have true MAT path by MM Paranum~~
* 12.) Put extra books as a basket.. use db instead of hardcode
* 13.) Add ~~chanting book~~ Theragatha, Therigatha, ~~DhpA (english)~~, JaA (english)  to downloads
* 14.) System menu so that if anki is installed, we can see it on system menu?
* 15.) Deep links.. add system menu to have TPR work. **partically implemented**
* 16.) ~~Better dictionary lookup vaharatiiti vaharatii'ti~~
* 17.) ~~Fix highlight (click to dict) highlights all words~~
* 18.) Have TOC pop sub menu list before open book
* 19.) Have TPR remember last place for each book and go there on open.
* 20.) Include word count on dictionary
* 21.) Include search button on dictionary.
* 22.) ~~Keyboard shortcuts~~
* 23.) sticky highlights as bookmarks.. like kindle  **half done**
* 24.) ~~search in page~~

Old Road Map below:

# Phase 1:  
~~Decide on a new name:  Tipitaka Pali Reader~~
~~Add all English TPP dictionary support and word break.~~
Refresh the Pali from cscd disk.  (I will get most up to date from Frank Snow)
Automate One Click refresh to db (any language is fine).  **(I don't know what this is)**
~~Add to Play store.~~

# Phase 2:  
~~Merge the two programs (Tipitaka Pali and TPP) for android ios~~
~~Research how to display in desktop with webview replacement~~
~~Normalize the data in the database~~

# Phase 3
~~Desktop + Mobile:~~
~~Add multiview fo (M A T) similar and better than tipitaka.app and digitalpalireader.online~~
~~Research how to display in desktop without webview.  It does not look like anything is going to be written for desktop webview.~~
~~Simple html widgets exist~~
Consider simplifying the html
Normalize the paragraphs by db instead of <div>
 
Normalize the data in the database

# Phase 4
firestore implementation **some bookmark features are on cloud**
   ~~clud and multi-device sync for bookmarks~~  **sink not implemented**
   sticky group highlights **implemented with icons on each page**
   dictionary submission
   



# Philosophy Issues agreed on:
Flutter as base language
Sqlite
Better Normalization
Philosophy Issues needed for working together:
 **Display Page separation by MM pages required**
In phase II, we should have the ability to display the data in any separate method.  Ie. MM para num, PTS, MM Page, etc.  It needs to be thought out, however, for the history.
Continuous Scrolling books.  Sometimes, you just want to scroll to find something without using search methods.  This is part of TPP philosophy.
I was thinking of merging issue 1 with this.. We could have a vertical list with raised cards.  We could fill the individual cards by _getPaliByChosenSeparationMethod  -- or something like this.
Single Click / Tap word lookup.  
I believe this is important, but I am willing to sacrifice long press or double click for word selections.  There is a global gesture widget that can get any input.  This might be the prefered method.  There are widgets that exist with callbacks, some without .  This needs to be researched for Desktop Phase.


