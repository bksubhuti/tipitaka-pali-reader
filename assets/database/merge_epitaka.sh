#!/bin/bash

# Puts the ePitaka databases back together from their parts, for working on
# them outside the app. The app does the same thing at first run, reading the
# parts straight out of the bundle.

merge_one() {
  local prefix="$1"
  local file="$2"

  if ! ls "$prefix"* 1> /dev/null 2>&1; then
    echo "Skipping $file: no parts here"
    return
  fi

  echo "Merging parts into $file"
  cat "$prefix"* > "$file"
  echo "Deleting parts"
  rm "$prefix"*
}

merge_one epitaka_part. epitaka.db
merge_one tpr_extension_part. tpr_extension.db

echo success
