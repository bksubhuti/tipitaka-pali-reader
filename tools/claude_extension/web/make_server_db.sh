#!/bin/bash
# Makes the databases for the TPR Research web server from an installed TPR
# (by default ~/TPR/db, the copy TPR keeps for Claude): TPR builds the
# search index and joins its parts at install, so the server uses a
# finished set rather than the raw data release.
#
# The reader's own data is emptied first (reading history, searches,
# look-ups, bookmarks): the server is public, and tpr_query reads any table.
#
# Output: tpr-server-db.tar.zst, for the tpr_downloads release `server-db`,
# which setup_server.sh downloads.
set -euo pipefail
SRC=${1:-$HOME/TPR/db}
OUT=${2:-$(pwd)}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cp "$SRC/tipitaka_pali.db" "$SRC/epitaka.db" "$WORK/"
cp "$SRC"/lang_*.db "$WORK/" 2>/dev/null || true

sqlite3 "$WORK/tipitaka_pali.db" <<'SQL'
DELETE FROM recent;
DELETE FROM search_history;
DELETE FROM dictionary_history;
DELETE FROM bookmark;
DELETE FROM folder;
VACUUM;
SQL
for t in recent search_history dictionary_history bookmark folder; do
  n=$(sqlite3 "$WORK/tipitaka_pali.db" "SELECT count(*) FROM $t")
  [ "$n" = 0 ] || { echo "$t still has $n rows" >&2; exit 1; }
done

ls -l "$WORK"
tar -C "$WORK" -cf - . | zstd -19 -T0 -q -o "$OUT/tpr-server-db.tar.zst" -f
ls -l "$OUT/tpr-server-db.tar.zst"
