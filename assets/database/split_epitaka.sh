#!/bin/bash

# Splits the ePitaka databases the same way split.sh handles the Pali one:
# 50 MB parts, because a single asset that large does not copy reliably on
# every platform.
#
# Two files are shipped:
#   epitaka.db        ePitaka's sentences, headings and book links
#   tpr_extension.db  TPR's page boundaries, page markers and orphan flags
#
# Put both beside this script before running it. epitaka.db should already be
# trimmed to the tables TPR reads; the published one carries dictionaries and
# embeddings that more than double it for no use here.

set -u

split_one() {
  local file="$1"
  local prefix="$2"

  if [ ! -f "$file" ]; then
    echo "Skipping $file: not here"
    return
  fi

  if ls "$prefix"* 1> /dev/null 2>&1; then
    echo "Parts for $file already exist. Exiting to prevent accidental deletion."
    exit 1
  fi

  echo "Splitting $file per 50MB"
  split -b 50000k "$file" "$prefix"

  if [ $? -eq 0 ]; then
    echo "Deleting $file"
    rm "$file"
    echo "Split $file into $(ls "$prefix"* | wc -l) parts"
  else
    echo "Error splitting $file. Original kept."
    exit 1
  fi
}

split_one epitaka.db epitaka_part.
split_one tpr_extension.db tpr_extension_part.

echo "Success. Add the part names to pubspec.yaml and to AssetsFile in"
echo "lib/data/constants.dart if the number of parts has changed."
echo "Then run: shasum -a 256 *_part.* > SHA256SUMS"
echo "and upload the parts to the release the Linux build reads from."
