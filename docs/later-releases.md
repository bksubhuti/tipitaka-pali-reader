# For later releases

Work agreed but left out of the ePitaka release (#321). Roughly in order of
how much it matters.

## Cloud backup and restore of folders

The cloud dialog (`lib/ui/dialogs/bookmark_cloud_transfer_dialog.dart`,
`lib/services/repositories/bookmark_fire_repo.dart`) moves bookmarks one at a
time and sends no folders, no folder for each bookmark, and no order. A
bookmark restored from the cloud lands outside any folder.

Plan:

- **Back up:** one snapshot of the folder tree and every bookmark with its
  folder and position, to `users/<email>/backups`, encrypted with the existing
  key. Split across documents if it passes Firestore's 1 MB limit.
- **Restore:** replaces what is on the device, behind a confirmation giving
  the number of folders and bookmarks. Folder IDs are local, so every parent
  link and every bookmark's folder must be mapped from old to new. Test with
  nested folders.
- **Merge, later if wanted:** needs a permanent ID (UUID) on every folder and
  bookmark to tell the same item apart from a duplicate. Matching on content
  (same page, same folder name) breaks on renames and edited notes.
- The key is the account password, so a password change leaves older backups
  unreadable. Say so in the interface.

## Side by side: Pali and one translation

The Pali beside the first shown translation, in the same pane. The data
already lines each sentence up with its translation; the work is in the
reader.

- A third text display choice, beside the current ones.
- Each paragraph as a row of two blocks, Pali on the left and the translation
  on the right. Paragraph tops line up; sentences within a long paragraph
  drift, since English runs longer than Pali.
- Narrow panes, phones included, fall back to the translation beneath.
- Tapping a word, selecting, search highlight and the read-aloud highlight
  all need to work across two blocks, and an English word must not open the
  Pali dictionary.

About a day or two, on its own branch.

## Word splitting for languages without spaces

Myanmar, Thai, Khmer, Lao, Chinese and Japanese do not put spaces between
words. The translation index can only split where there are spaces, so a
"word" in it is a whole run of text. A search finds a word that starts a run;
one inside a longer run is found only with "any part", which is slower.
Splitting these languages into words properly needs a dictionary-based word
breaker when the index is built.

## The "on this device" dialog

On the translation choice screen, a language copied before the release date
was recorded (any copy installed before 2 October 2026) shows its install
date next to the online release date. The install date is always the newer
one, so it reads as if the copy were newer. It should not quote the install
date as if it were a version date. New installs record the release date and
compare correctly.

## Smaller items

- **Read aloud on Windows** has not been tested.
- **`tika_sa_05` page data:** `page_break` has a stray page 32 on paragraph 1,
  before the book's first page, 393. The app copes with it. It belongs in
  the extension tooling.
- **`test/sentence_search_test.dart`** opens a database at a fixed Windows
  path and fails on every other machine. It needs the same `TPR_DATA_DIR`
  switch as `test/paragraph_read_test.dart`.
- **App size:** about 190 MB per processor type, nearly all of it bundled
  dictionaries (DPD and the others, about 420 MB unpacked). Making the
  dictionaries a separate download would shrink it most.
