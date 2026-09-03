#!/usr/bin/env bash
# Exit on error
set -e

echo "=========================================="
echo "Uninstalling Tipitaka Pali Reader..."
echo "=========================================="

rm -f "$HOME/.local/bin/tipitaka_pali_reader"
rm -f "$HOME/.local/share/icons/tipitaka_pali_reader.png"
rm -f "$HOME/.local/share/applications/tipitaka_pali_reader.desktop"

# Update desktop launcher database
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$HOME/.local/share/applications"
fi

echo "=========================================="
echo "✅ Uninstallation completed successfully!"
echo "=========================================="
