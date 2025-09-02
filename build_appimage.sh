#!/usr/bin/env bash
set -euo pipefail

# Allow overrides via env vars; sensible defaults for CI
APPDIR="${APPDIR:-TipitakaPaliReader.AppDir}"
BUNDLE_DIR="${BUILD_BUNDLE_DIR:-build/linux/x64/release/bundle}"
APPIMAGE_TOOL="${APPIMAGE_TOOL:-./appimagetool-x86_64.AppImage}"
OUTPUT_APPIMAGE="${OUTPUT_APPIMAGE:-./tipitaka_pali_reader.AppImage}"

echo "AppDir        : $APPDIR"
echo "Bundle dir    : $BUNDLE_DIR"
echo "AppImage tool : $APPIMAGE_TOOL"
echo "Output        : $OUTPUT_APPIMAGE"

# Copy compiled bundle into AppDir
cd "$APPDIR"
cp -r "../$BUNDLE_DIR/"* .

# Back to repo root
cd ..

# Ensure run permissions
chmod +x "$APPDIR/AppRun" || true
chmod +x "$APPDIR/tipitaka_pali_reader" || true

# Build AppImage
"$APPIMAGE_TOOL" "$APPDIR/" "$OUTPUT_APPIMAGE"

echo "Built AppImage at: $OUTPUT_APPIMAGE"
