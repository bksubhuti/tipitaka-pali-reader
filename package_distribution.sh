#!/usr/bin/env bash
# Exit on error
set -e

DIST_DIR="tipitaka-pali-reader-linux"
ZIP_NAME="tipitaka_pali_reader_linux.zip"

echo "Creating distribution package folder..."
rm -rf "$DIST_DIR"
rm -f "$ZIP_NAME"
mkdir -p "$DIST_DIR"

# 1. Copy the AppImage, Desktop entry, and Logo
echo "Copying application binaries and assets..."
if [ ! -f "tipitaka_pali_reader.AppImage" ]; then
  echo "Error: tipitaka_pali_reader.AppImage not found in the root directory!"
  echo "Please build the AppImage first (e.g., by running sh build_appimage2.sh)"
  exit 1
fi

cp tipitaka_pali_reader.AppImage "$DIST_DIR/"
cp TipitakaPaliReader.AppDir/logo.png "$DIST_DIR/"
cp TipitakaPaliReader.AppDir/tipitaka_pali_reader.desktop "$DIST_DIR/"

# 2. Write the install.sh script
echo "Writing install.sh script..."
cat << 'EOF' > "$DIST_DIR/install.sh"
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
EOF
chmod +x "$DIST_DIR/install.sh"

# 3. Write the uninstall.sh script
echo "Writing uninstall.sh script..."
cat << 'EOF' > "$DIST_DIR/uninstall.sh"
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
EOF
chmod +x "$DIST_DIR/uninstall.sh"

# 4. Write a simple README.txt
echo "Writing README.txt..."
cat << 'EOF' > "$DIST_DIR/README.txt"
Tipitaka Pali Reader - Linux Installation Guide
===============================================

This package contains:
1. tipitaka_pali_reader.AppImage (The main application binary)
2. logo.png (The application icon)
3. tipitaka_pali_reader.desktop (Desktop menu integration file)
4. install.sh (Easy installation script)
5. uninstall.sh (Uninstallation script)

How to Install:
--------------
1. Open a terminal in this directory.
2. Run the installation script:
   sh install.sh
3. You can now close the terminal and find "Tipitaka Pali Reader" in your applications launcher.

How to Uninstall:
----------------
1. Open a terminal in this directory.
2. Run the uninstallation script:
   sh uninstall.sh
EOF

# 5. Zip it up
echo "Zipping distribution package..."
zip -r "$ZIP_NAME" "$DIST_DIR"

# 6. Clean up temporary directory
rm -rf "$DIST_DIR"

echo "=========================================="
echo "✅ Package created successfully: $ZIP_NAME"
echo "=========================================="
