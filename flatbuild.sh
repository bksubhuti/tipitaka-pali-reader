#!/bin/bash
# Build the Linux app inside the Freedesktop SDK, as build_linux.yml does.
# Keep RUNTIME and LLVM in step with that workflow and the Flathub manifest.
set -e

# An SDK already installed can be used instead, matching the manifest's
# runtime-version: RUNTIME=25.08 LLVM=llvm20 ./flatbuild.sh
RUNTIME=${RUNTIME:-26.08}
LLVM=${LLVM:-llvm22}

# The SDK and its clang come separately: without the LLVM extension for this
# runtime, /usr/lib/sdk/$LLVM is empty and CMake cannot find a C++ compiler.
# Downloaded only when missing.
installed=$(flatpak list --runtime --columns=application,branch)
if ! grep -qP "^org\.freedesktop\.Sdk\t$RUNTIME$" <<<"$installed" ||
   ! grep -qP "^org\.freedesktop\.Sdk\.Extension\.$LLVM\t$RUNTIME$" <<<"$installed"; then
  flatpak remote-add --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak install --system -y --noninteractive flathub \
    "org.freedesktop.Sdk//$RUNTIME" \
    "org.freedesktop.Sdk.Extension.$LLVM//$RUNTIME"
fi

flatpak run \
  --filesystem=$HOME \
  --share=network \
  --devel \
  --env=FLATPAK_ENABLE_SDK_EXT=$LLVM \
  --env=FLUTTER_ROOT=$HOME/flutter \
  --env=PATH=$HOME/flutter/bin:/usr/lib/sdk/$LLVM/bin:/usr/bin:/bin \
  --env=CC=/usr/lib/sdk/$LLVM/bin/clang \
  --env=CXX=/usr/lib/sdk/$LLVM/bin/clang++ \
  --env=CMAKE_TOOLCHAIN_FILE=$HOME/git/tipitaka-pali-reader/clang_toolchain.cmake \
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
  export CC=$FOUND/clang CXX=$FOUND/clang++ PATH=$HOME/flutter/bin:$FOUND:/usr/bin:/bin
  echo "Using $CXX"
fi
"$CXX" --version | head -1

cd ~/git/tipitaka-pali-reader

# Clean old build cache (required for CMake to reconfigure)
rm -rf build/linux/x64/release

# Build with Flutter
flutter build linux --release

EOF

# Clean up sandbox CMake cache to restore host build compatibility
sh unsandbox.sh
