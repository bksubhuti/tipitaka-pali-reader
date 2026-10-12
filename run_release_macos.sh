#!/bin/bash
# Builds this tree as a macOS release app and opens it, to try a change in
# the app as people get it.
#
# It has the same bundle id as the installed app (org.americanmonk.tpp), so
# it opens the same books, settings and bookmarks. The two cannot run at
# once, so whichever is open is quit first.
#
#   ./run_release_macos.sh          build and open
#   ./run_release_macos.sh --open   open the last build without building

set -e
cd "$(dirname "$0")"

APP="build/macos/Build/Products/Release/tipitaka_pali_reader.app"

osascript -e 'tell application id "org.americanmonk.tpp" to quit' 2>/dev/null || true
# Give it a moment to close before the new one starts.
while [ "$(osascript -e 'application id "org.americanmonk.tpp" is running' 2>/dev/null)" = "true" ]; do
  sleep 0.5
done

if [ "$1" != "--open" ]; then
  flutter build macos --release
fi

echo "Opening $APP"
open "$APP"
