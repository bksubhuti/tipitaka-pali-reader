#!/bin/bash
# Packs the same extension for Codex as tpr-research-codex.zip, which TPR's
# "Codex setup" downloads, unpacks into ~/TPR/codex and registers in
# ~/.codex/config.toml (plus the skill in ~/.codex/skills/tpr-research).
# The server is the one Claude Desktop runs; manifest.json goes along
# because the server reads its version and prompts from it.
set -euo pipefail
cd "$(dirname "$0")"
rm -f tpr-research-codex.zip
zip -r -X -q tpr-research-codex.zip manifest.json icon.png server -x '*.DS_Store'
(cd codex && zip -X -q ../tpr-research-codex.zip SKILL.md)
unzip -l tpr-research-codex.zip
