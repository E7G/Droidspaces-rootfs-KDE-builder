#!/bin/bash
set -euo pipefail

# Build Hangover for Mi Pad 4 / SDM660 / Adreno 512
# Hangover provides ARM64 Wine with FEX/Box64 PE CPU translation

HANGOVER_COMMIT="febcd000f701c18dc28698870bf84ab7229a7009"
BUILD_DIR=".ci/hangover"
OUTPUT_DIR="hangover-mi-pad4"
STAGE="$PWD/$OUTPUT_DIR"

rm -rf "$BUILD_DIR" "$OUTPUT_DIR"

# Download llvm-mingw prebuilt toolchain
LLVM_MINGW_VER="20260616"
curl -L \
  "https://github.com/mstorsjo/llvm-mingw/releases/download/${LLVM_MINGW_VER}/llvm-mingw-${LLVM_MINGW_VER}-ucrt-ubuntu-24.04-aarch64.tar.xz" \
  -o /tmp/llvm-mingw.tar.xz
sudo mkdir -p /opt/llvm-mingw
sudo tar -xJf /tmp/llvm-mingw.tar.xz \
  --strip-components=1 \
  -C /opt/llvm-mingw

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
export PATH="/opt/llvm-mingw/bin:$PATH"
../configure \
  --disable-tests \
  --with-mingw=clang \
  --enable-archs=arm64ec,aarch64,i386 \
  --prefix=/usr/local
make -j"$(nproc)"
make DESTDIR="$STAGE" install

# Build FEX ARM64EC DLL for x86_64 Windows apps
cd "$PWD/../../fex"
mkdir -p build_ec
cd build_ec
cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE=../Data/CMake/toolchain_mingw.cmake \
  -DENABLE_LTO=False \
  -DMINGW_TRIPLE=arm64ec-w64-mingw32 \
  -DBUILD_TESTS=False \
  ..
cmake --build . -j"$(nproc)" --target arm64ecfex
install -Dm755 \
  Bin/libarm64ecfex.dll \
  "$STAGE/usr/local/lib/wine/aarch64-windows/libarm64ecfex.dll"

cd ../..

# Create minimal runtime package
cp -r "$OUTPUT_DIR"/* .
chmod +x usr/local/bin/hangover

echo "Hangover built successfully for Mi Pad 4"