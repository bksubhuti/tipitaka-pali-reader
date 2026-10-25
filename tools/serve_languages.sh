#!/bin/sh
# Serves the ePitaka language archives from this computer, so a debug run can
# install a translation in seconds instead of downloading it.
#
#   tools/serve_languages.sh [folder of epitaka_*.zip] [port]
#
# Then start TPR with --dart-define=TPR_LANG_URL=http://127.0.0.1:8765, as
# the "TPR (languages from this Mac)" entry in .vscode/launch.json does.
# Without that flag TPR downloads from the GitHub releases as usual; release
# builds never have it. Ctrl+C stops the server.

SOURCE=${1:-$HOME/git/epitaka}
PORT=${2:-8765}

# The names TPR asks for. English is kept here as epitaka_en_new.zip.
SERVED=$(mktemp -d)
trap 'rm -rf "$SERVED"' EXIT
for zip in "$SOURCE"/epitaka_*.zip; do
  ln -s "$zip" "$SERVED/$(basename "$zip")"
done
[ -e "$SOURCE/epitaka_en_new.zip" ] &&
  ln -sf "$SOURCE/epitaka_en_new.zip" "$SERVED/epitaka_en.zip"

echo "Serving $(ls "$SERVED" | wc -l | tr -d ' ') archives from $SOURCE on http://127.0.0.1:$PORT"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$SERVED"
