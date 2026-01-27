#!/usr/bin/env bash
#set -euo pipefail

# Defaults (overridable via env)
APPDIR="${APPDIR:-TipitakaPaliReader.AppDir}"
BUNDLE_DIR="${BUILD_BUNDLE_DIR:-build/linux/x64/release/bundle}"
OUTPUT_APPIMAGE="${OUTPUT_APPIMAGE:-./tipitaka_pali_reader.AppImage}"

# Detect arch & choose proper tool name
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)   TOOL_NAME="appimagetool-x86_64.AppImage" ;;
  aarch64|arm64) TOOL_NAME="appimagetool-aarch64.AppImage" ;;
  *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

APPIMAGE_TOOL="${APPIMAGE_TOOL:-./$TOOL_NAME}"
APPIMAGE_URL="${APPIMAGE_URL:-https://github.com/AppImage/AppImageKit/releases/download/continuous/$TOOL_NAME}"

echo "AppDir         : $APPDIR"
echo "Bundle dir     : $BUNDLE_DIR"
echo "Tool (path)    : $APPIMAGE_TOOL"
echo "Tool (download): $APPIMAGE_URL"
echo "Output         : $OUTPUT_APPIMAGE"

# Fetch appimagetool if not present
if [[ ! -x "$APPIMAGE_TOOL" ]]; then
  echo "Downloading appimagetool..."
  curl -fsSL "$APPIMAGE_URL" -o "$APPIMAGE_TOOL"
  chmod +x "$APPIMAGE_TOOL"
fi

# Copy compiled bundle into AppDir
mkdir -p "$APPDIR"
cp -r "$BUNDLE_DIR"/. "$APPDIR"/

# Configure deeplink support for Linux
echo "🔗 Configuring deeplink support..."

# Update desktop file with MIME type for deeplinks
if [ -f "$APPDIR/tipitaka_pali_reader.desktop" ]; then
  # Ensure MimeType is present (add if missing)
  if ! grep -q "MimeType=x-scheme-handler/tipitaka" "$APPDIR/tipitaka_pali_reader.desktop"; then
    echo "Adding MimeType for deeplink support..."
    echo "MimeType=x-scheme-handler/tipitaka;" >> "$APPDIR/tipitaka_pali_reader.desktop"
  fi
fi

# Update AppRun to pass arguments to the application
if [ -f "$APPDIR/AppRun" ]; then
  # Ensure AppRun passes arguments ($@)
  if ! grep -q "exec.*\$@" "$APPDIR/AppRun"; then
    echo "Updating AppRun to pass arguments..."
    cat > "$APPDIR/AppRun" << 'EOF'
#!/bin/sh
cd "$(dirname "$0")"
exec ./tipitaka_pali_reader "$@"
EOF
  fi
  chmod +x "$APPDIR/AppRun"
fi

# Ensure run permissions for your app launchers (ignore if absent)
chmod +x "$APPDIR/tipitaka_pali_reader" 2>/dev/null || true

# Build AppImage
"$APPIMAGE_TOOL" "$APPDIR/" "$OUTPUT_APPIMAGE"

echo "✅ Built AppImage at: $OUTPUT_APPIMAGE"
