#!/bin/bash
# Build the Flathub package locally, as build_linux.yml does, and test it:
#   1. build the app inside the Freedesktop SDK
#   2. pack it with flathub/ into tpr_<build>.tar.gz and its .sha256
#   3. build the flatpak from flathub/org.americanmonk.TipitakaPaliReader.yml,
#      using that tarball in place of the release download
# Everything it writes goes in build/flathub/, which git ignores.
# Keep RUNTIME and LLVM in step with that workflow and the Flathub manifest.
set -e

# An SDK already installed can be used instead, matching the manifest's
# runtime-version: RUNTIME=25.08 LLVM=llvm20 ./flatbuild.sh
RUNTIME=${RUNTIME:-26.08}
LLVM=${LLVM:-llvm22}

APP_ID=org.americanmonk.TipitakaPaliReader
cd "$(dirname "$0")"
APP_DIR=$PWD
OUT=$APP_DIR/build/flathub

PUBSPEC_VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')
BUILD_NUM=${PUBSPEC_VERSION##*+}
TARBALL=tpr_$BUILD_NUM.tar.gz
echo "Version $PUBSPEC_VERSION, build $BUILD_NUM"

# The host's Flutter, found from PATH (e.g. ~/develop/flutter).
if [ -z "$FLUTTER_ROOT" ]; then
  FLUTTER_BIN=$(command -v flutter) || { echo "flutter not found in PATH"; exit 1; }
  FLUTTER_ROOT=$(dirname "$(dirname "$(readlink -f "$FLUTTER_BIN")")")
fi

# The same checks as build_linux.yml. The SHA256SUMS one only warns here, so
# a database being worked on can still be built and tried.
expected=$(grep -oE 'assets/database/[a-z_]+_part\.[a-z]+' pubspec.yaml | sort)
actual=$(ls assets/database/*_part.* | sort)
if [ "$expected" != "$actual" ]; then
  echo "Database parts do not match pubspec.yaml."
  echo "pubspec.yaml:"; echo "$expected"
  echo "assets/database:"; echo "$actual"
  exit 1
fi
if ! (cd assets/database && sha256sum --quiet -c SHA256SUMS); then
  echo "WARNING: the database parts above differ from SHA256SUMS; the release build would stop here"
fi

# The SDK and its clang come separately: without the LLVM extension for this
# runtime, /usr/lib/sdk/$LLVM is empty and CMake cannot find a C++ compiler.
# Nothing is downloaded unless asked: when one is missing, the script stops
# and shows the command; DOWNLOAD=1 sh flatbuild.sh installs it instead.
# The SDK is run from the system installation; the extension is found in
# either the user or the system installation.
installed=$(flatpak list --runtime --columns=application,branch,installation)
# has_runtime APP [INSTALLATION]
has_runtime() {
  printf '%s\n' "$installed" |
    awk -v app="$1" -v branch="$RUNTIME" -v inst="$2" \
      '$1 == app && $2 == branch && (inst == "" || $3 == inst) { found = 1 } END { exit !found }'
}
missing=
has_runtime org.freedesktop.Sdk system || missing="$missing org.freedesktop.Sdk//$RUNTIME"
has_runtime "org.freedesktop.Sdk.Extension.$LLVM" ||
  missing="$missing org.freedesktop.Sdk.Extension.$LLVM//$RUNTIME"
if [ -n "$missing" ] && [ "$DOWNLOAD" != 1 ]; then
  echo "Not installed:$missing"
  echo "Nothing was downloaded. To download and install them (large):"
  echo "  flatpak install --system --no-related flathub$missing"
  echo "or run: DOWNLOAD=1 sh flatbuild.sh"
  exit 1
fi
if [ -n "$missing" ]; then
  flatpak remote-add --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
  # --no-related: only what is named, not the GL drivers, codecs and
  # translations flatpak would otherwise fetch or update alongside.
  flatpak install --system -y --noninteractive --no-related flathub $missing
fi

# 1. Build inside the SDK
flatpak run --system \
  --filesystem=$HOME \
  --share=network \
  --devel \
  --env=FLATPAK_ENABLE_SDK_EXT=$LLVM \
  --env=APP_DIR=$APP_DIR \
  --env=FLUTTER_ROOT=$FLUTTER_ROOT \
  --env=PATH=$FLUTTER_ROOT/bin:/usr/lib/sdk/$LLVM/bin:/usr/bin:/bin \
  --env=CC=/usr/lib/sdk/$LLVM/bin/clang \
  --env=CXX=/usr/lib/sdk/$LLVM/bin/clang++ \
  --env=CMAKE_TOOLCHAIN_FILE=$APP_DIR/clang_toolchain.cmake \
  --command=bash \
  "org.freedesktop.Sdk//$RUNTIME" <<'EOF'
set -e

# Use the expected clang, or else whichever LLVM extension is mounted.
if [ ! -x "$CXX" ]; then
  echo "No clang++ at $CXX. SDK extensions mounted: $(ls /usr/lib/sdk 2>/dev/null)"
  FOUND=$(ls -d /usr/lib/sdk/llvm*/bin 2>/dev/null | sort -V | tail -1)
  if [ -z "$FOUND" ]; then
    echo "No LLVM extension mounted. Installed: $(ls /usr/lib/sdk 2>/dev/null)"
    exit 1
  fi
  export CC=$FOUND/clang CXX=$FOUND/clang++ PATH=$FLUTTER_ROOT/bin:$FOUND:/usr/bin:/bin
  echo "Using $CXX"
fi
"$CXX" --version | head -1

cd "$APP_DIR"

# Clean old build cache (required for CMake to reconfigure)
rm -rf build/linux/x64/release

# Regenerate the localizations from the .arb files, as build_linux.yml does
flutter gen-l10n

# Build with Flutter
flutter build linux --release

EOF

# Clean up sandbox CMake cache to restore host build compatibility
sh unsandbox.sh

# 2. Pack the tarball as build_linux.yml does: flathub/ with the bundle in bin/
rm -rf "$OUT/tpr" "$OUT/$TARBALL" "$OUT/$TARBALL.sha256"
mkdir -p "$OUT/tpr/bin"
cp -r flathub/icons flathub/$APP_ID.desktop flathub/$APP_ID.xml "$OUT/tpr/"
cp -r build/linux/x64/release/bundle/* "$OUT/tpr/bin/"
chmod +x "$OUT/tpr/bin/tipitaka_pali_reader"
(cd "$OUT/tpr" && tar -czf "../$TARBALL" bin icons $APP_ID.desktop $APP_ID.xml)
(cd "$OUT" && sha256sum "$TARBALL" > "$TARBALL.sha256")
echo "Packed build/flathub/$TARBALL"

# 3. Build the flatpak from the Flathub manifest, with the local tarball as
# its source in place of the release download. It runs in the Platform, as
# from Flathub, or else in the SDK, which holds all of the Platform, so
# nothing more is downloaded.
TEST_RUNTIME=org.freedesktop.Platform
has_runtime $TEST_RUNTIME || TEST_RUNTIME=org.freedesktop.Sdk
sed -e "s|^\( *\)url: .*|\1path: $TARBALL|" -e '/^ *sha256:/d' \
  -e "s|^runtime: org.freedesktop.Platform|runtime: $TEST_RUNTIME|" \
  flathub/$APP_ID.yml > "$OUT/$APP_ID.yml"
# Installed for the user, beside the Flathub one in the system installation.
flatpak-builder --user --install --force-clean \
  --state-dir="$OUT/.flatpak-builder" \
  "$OUT/build-dir" "$OUT/$APP_ID.yml"

echo
echo "Installed for the user. Running it: flatpak run --user $APP_ID"
echo "For Flathub, the release's tpr_$BUILD_NUM.tar.gz and its sha256 go in"
echo "flathub/$APP_ID.yml, then that file is copied to the flathub repo."
flatpak run --user $APP_ID
