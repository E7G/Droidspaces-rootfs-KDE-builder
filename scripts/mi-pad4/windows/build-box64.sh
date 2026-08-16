#!/bin/bash
set -euo pipefail

# Build Box64 for Mi Pad 4 / SDM660 / Adreno 512
# Optimized for Android hybrid kernel environment

BOX64_VERSION="0.2.4"
BUILD_DIR=".ci/box64"
OUTPUT_DIR="box64-mi-pad4"

rm -rf "$BUILD_DIR" "$OUTPUT_DIR"

git clone \
  --depth 1 \
  --branch v${BOX64_VERSION} \
  https://github.com/ptitSeb/box64.git \
  "$BUILD_DIR"

cd "$BUILD_DIR"

mkdir -p build
cd build

cmake .. \
  -DARM64=ON \
  -DARM_DYNAREC=ON \
  -DBAD_SIGNAL=ON \
  -DBOX32=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr/local

make -j$(nproc)

make install DESTDIR="$PWD/../../$OUTPUT_DIR"

cd ../..

# Create minimal runtime package
cp -r "$OUTPUT_DIR"/* .
chmod +x usr/local/bin/box64

echo "Box64 built successfully for Mi Pad 4"