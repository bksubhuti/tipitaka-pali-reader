#!/bin/bash
# Packs the extension into tpr-research.mcpb, the file readers open to
# install it in Claude Desktop. An .mcpb is a zip of this folder with
# manifest.json at the top. Anthropic's mcpb tool is used when npx can
# reach it, since it also checks the manifest; otherwise plain zip.
set -euo pipefail
cd "$(dirname "$0")"
rm -f tpr-research.mcpb
if command -v npx >/dev/null && npx -y @anthropic-ai/mcpb validate manifest.json; then
  npx -y @anthropic-ai/mcpb pack . tpr-research.mcpb
else
  echo "mcpb tool not available; packing with zip"
  zip -r -X -q tpr-research.mcpb manifest.json icon.png README.md server -x '*.DS_Store'
fi
ls -l tpr-research.mcpb
