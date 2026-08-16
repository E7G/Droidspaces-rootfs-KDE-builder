#!/bin/bash
set -euo pipefail

# Build Hangover for Mi Pad 4 / SDM660 / Adreno 512
# Hangover provides ARM64 Wine with FEX/Box64 PE CPU translation

HANGOVER_VERSION="10.0"
BUILD_DIR=".ci/hangover"
OUTPUT_DIR="hangover-mi-pad4"

rm -rf "$BUILD_DIR" "$OUTPUT_DIR"

git clone \
  --depth 1 \
  --branch hangover-${HANGOVER_VERSION} \
  https://github.com/andrerh/hangover.git \
  "$BUILD_DIR"

cd "$BUILD_DIR"

mkdir -p build
cd build

cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DENABLE_PE=ON \
  -DENABLE_FEX=ON

make -j$(nproc)

make install DESTDIR="$PWD/../../$OUTPUT_DIR"

cd ../..

# Create minimal runtime package
cp -r "$OUTPUT_DIR"/* .
chmod +x usr/local/bin/hangover

echo "Hangover built successfully for Mi Pad 4"