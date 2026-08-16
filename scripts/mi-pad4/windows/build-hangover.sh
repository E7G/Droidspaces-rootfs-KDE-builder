#!/bin/bash
set -euo pipefail

# Build Hangover for Mi Pad 4 / SDM660 / Adreno 512
# Hangover provides ARM64 Wine with FEX/Box64 PE CPU translation

HANGOVER_COMMIT="febcd000f701c18dc28698870bf84ab7229a7009"
BUILD_DIR=".ci/hangover"
OUTPUT_DIR="hangover-mi-pad4"
STAGE="$PWD/$OUTPUT_DIR"

rm -rf "$BUILD_DIR" "$OUTPUT_DIR"

# Clone Hangover with submodules
git clone \
  --recurse-submodules \
  https://github.com/AndreRH/hangover.git \
  "$BUILD_DIR"

cd "$BUILD_DIR"
git checkout "$HANGOVER_COMMIT"
git submodule update --init --recursive

# Build Wine with Hangover patches
mkdir -p wine/build
cd wine/build
../configure \
  --disable-tests \
  --with-mingw=clang \
  --enable-archs=arm64ec,aarch64,i386 \
  --prefix=/usr/local
make -j"$(nproc)"
make DESTDIR="$STAGE" install

cd ../..

# Create minimal runtime package
cp -r "$OUTPUT_DIR"/* .
chmod +x usr/local/bin/hangover

echo "Hangover built successfully for Mi Pad 4"