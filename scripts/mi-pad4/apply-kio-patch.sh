#!/bin/bash
set -euo pipefail

# Apply KIO runtime named socket patch to PKGBUILD
# This script assumes it's run from the repository root

PKGBUILD_PATH=".ci/kio/PKGBUILD"

# Modify arch
sed -i "s/^arch=(.*)$/arch=('aarch64')/" "$PKGBUILD_PATH"

# Add patch to source array
echo "source+=(kio-runtime-named-socket.patch)" >> "$PKGBUILD_PATH"
echo "sha256sums+=('SKIP')" >> "$PKGBUILD_PATH"
echo "" >> "$PKGBUILD_PATH"

# Add prepare() function
cat >> "$PKGBUILD_PATH" << 'PKGBUILD_EOF'

prepare() {
  cd "$srcdir/kio-$pkgver"
  patch -Np1 -i "$srcdir/kio-runtime-named-socket.patch"
}
PKGBUILD_EOF