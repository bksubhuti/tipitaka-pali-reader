# Tipitaka Pali Reader - Linux Deeplink Support

## Overview
The Linux AppImage now supports deeplinks via the `tipitaka://` URL scheme. This allows opening specific suttas directly from web links or terminal commands.

## Usage Methods

### 1. Web Browser Links
Click on any `tipitaka://` link from websites, documents, or HTML files:

```
<a href="tipitaka://open?sutta=mn118">MN 118 - Mindfulness of Breathing</a>
<a href="tipitaka://open?sutta=dn1">DN 1 - Brahma's Net</a>
<a href="tipitaka://open?sutta=sn56.11">SN 56.11 - The Four Noble Truths</a>
<a href="tipitaka://open?sutta=an1.1">AN 1.1 - Mindfulness is the Way</a>
```

### 2. Terminal Commands

#### Direct App Launch with Deeplink
```bash
./tipitaka_pali_reader.AppImage "tipitaka://open?sutta=mn118"
```

#### System URL Handler (xdg-open)
```bash
xdg-open "tipitaka://open?sutta=sn56.11"
```

## URL Format

The deeplink URL format is:
```
tipitaka://open?sutta={SUTTA_ID}
```

### Examples:
- `tipitaka://open?sutta=mn118` - Opens MN 118 (Ānāpānasati Sutta)
- `tipitaka://open?sutta=dn1` - Opens DN 1 (Brahmajāla Sutta)
- `tipitaka://open?sutta=sn56.11` - Opens SN 56.11 (Dhammacakkappavattana Sutta)

## System Integration

### Automatic Installation (from AppImage)
```bash
# 1. Extract AppImage to register with system
./tipitaka_pali_reader.AppImage --appimage-extract

# 2. Install desktop file system-wide
sudo cp squashfs-root/tipitaka_pali_reader.desktop /usr/share/applications/
sudo cp squashfs-root/logo.png /usr/share/icons/hicolor/256x256/apps/

# 3. Update desktop database
sudo update-desktop-database /usr/share/applications

# 4. Set as default URL handler
xdg-settings set default-url-scheme-handler tipitaka tipitaka_pali_reader.desktop
```

### User Installation (no sudo required)
```bash
# Install for current user only
mkdir -p ~/.local/share/applications
cp squashfs-root/tipitaka_pali_reader.desktop ~/.local/share/applications/
mkdir -p ~/.local/share/icons/hicolor/256x256/apps/
cp squashfs-root/logo.png ~/.local/share/icons/hicolor/256x256/apps/

# Update databases
update-desktop-database ~/.local/share/applications
xdg-settings set default-url-scheme-handler tipitaka tipitaka_pali_reader.desktop
```

## Testing

### Test with HTML File
```bash
# Create test HTML (included in repository)
xdg-open test_deeplinks.html
```

### Test from Terminal
```bash
# Launch app first
./tipitaka_pali_reader.AppImage &

# Test with different suttas
xdg-open "tipitaka://open?sutta=mn118"
xdg-open "tipitaka://open?sutta=sn56.11"
```

## Technical Implementation

### What Changed

1. **Desktop File**: Added `MimeType=x-scheme-handler/tipitaka;`
2. **AppRun Script**: Modified to pass arguments (`"$@"`) to application
3. **Build Script**: Enhanced to automatically configure deeplink support
4. **Flutter App**: Added command line argument detection and URL handling
5. **MIME Registration**: Created `tipitaka.xml` for proper system integration

### Cross-Platform Support

- ✅ **Android**: Intent filter configured in AndroidManifest.xml
- ✅ **macOS**: URL scheme registered in Info.plist  
- ✅ **Linux**: MIME type and desktop file configured
- ✅ **Web Links**: Works from browsers and HTML pages

## Notes

- Links from browsers work correctly and open the specified sutta
- Multiple app instances may be created (each link click launches new instance)
- For production use, users should install the desktop file system-wide
- The deeplink functionality is compatible with all major suttas in the Tipitaka database

## Building

To build with deeplink support:

```bash
# Build AppImage with automatic deeplink configuration
./build_appimage2.sh
```

The build script automatically:
- Updates desktop file with MIME type
- Configures AppRun to pass arguments  
- Creates final AppImage with deeplink support