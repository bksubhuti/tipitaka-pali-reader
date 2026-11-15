#!/bin/zsh
# Starts TPR on this Mac as a brand-new install: its data and settings go to
# the Trash. Quit TPR first.
C=~/Library/Containers/org.americanmonk.tpp/Data
if pgrep -f "tipitaka_pali_reader|Tipitaka Pali Reader" >/dev/null; then
  echo "TPR is running. Quit it first."; exit 1
fi
setopt null_glob
items=()
for f in "$C/Library/Application Support/org.americanmonk.tpp/"* \
         "$C/Library/Preferences/org.americanmonk.tpp.plist"; do
  [[ -e $f ]] && items+=("$f")
done
if (( ${#items} == 0 )); then echo "Already clean."; exit 0; fi
trash=~/.Trash/tpr_data_$(date +%Y%m%d_%H%M%S)
mkdir -p "$trash"
mv "${items[@]}" "$trash/"
killall cfprefsd 2>/dev/null
echo "TPR data moved to the Trash. Next start is a fresh install."
