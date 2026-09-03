#!/usr/bin/env bash
# Exit on error
set -e

echo "=========================================="
echo "Installing Tipitaka Pali Reader..."
echo "=========================================="

# Create standard user directories if they don't exist
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.local/share/applications"
mkdir -p "$HOME/.local/share/icons"

# Get absolute path of this script directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Copy AppImage to user bin and make executable
echo "Installing AppImage..."
cp "$DIR/tipitaka_pali_reader.AppImage" "$HOME/.local/bin/tipitaka_pali_reader"
chmod +x "$HOME/.local/bin/tipitaka_pali_reader"

# Copy logo icon
echo "Installing icon..."
cp "$DIR/logo.png" "$HOME/.local/share/icons/tipitaka_pali_reader.png"

# Copy and update Desktop entry with absolute paths
echo "Installing desktop entry..."
DESKTOP_FILE="$HOME/.local/share/applications/tipitaka_pali_reader.desktop"

cat << EOM > "$DESKTOP_FILE"
[Desktop Entry]
Version=1.0
Type=Application
Terminal=false
Name=Tipitaka Pali Reader
Exec=$HOME/.local/bin/tipitaka_pali_reader %u
Icon=$HOME/.local/share/icons/tipitaka_pali_reader.png
Categories=Utility;
StartupWMClass=tipitaka_pali_reader
MimeType=x-scheme-handler/tpr.pali.tools;
EOM

chmod +x "$DESKTOP_FILE"

# Associate custom URL scheme if xdg-mime is available
if command -v xdg-mime >/dev/null 2>&1; then
  echo "Registering custom URL scheme handler..."
  xdg-mime default tipitaka_pali_reader.desktop x-scheme-handler/tpr.pali.tools
fi

# Update desktop launcher database
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$HOME/.local/share/applications"
fi

echo "=========================================="
echo "✅ Installation completed successfully!"
echo "You can now launch 'Tipitaka Pali Reader' from your application menu/launcher."
echo "=========================================="
