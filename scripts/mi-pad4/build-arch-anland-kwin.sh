#!/bin/bash
set -euo pipefail

# Build Anland KWin/Xwayland with Arch's own Qt/ABI.  Fedora RPM payloads must
# not be copied into Arch: they link against Fedora's private Qt ABI.

case "${BUILD_KDE:-}" in
    min|conc) ;;
    *) exit 0 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT=/tmp/droidspaces-arch-anland-build
KWINKG=365ae0acc5f521f53a85fe6d9a030646687324f8
XWAYLANDKG=8f82d79d312192108bb6417187c6ea986cdfcb3c

pacman -S --noconfirm --needed \
    base-devel cmake ninja meson extra-cmake-modules kdoctools krunner \
    plasma-wayland-protocols python vulkan-headers wayland-protocols \
    xorgproto xtrans xorg-font-util xorg-xwayland libcap

install -d -m 0755 /etc/sudoers.d
printf '%s\n' 'user ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/droidspaces-user
chmod 0440 /etc/sudoers.d/droidspaces-user

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT"

clone_at() {
    local url="$1" commit="$2" dir="$3"
    git clone --filter=blob:none --no-checkout "$url" "$dir"
    git -C "$dir" fetch --depth=1 origin "$commit"
    git -C "$dir" checkout --detach "$commit"
}

build_kwin() {
    local dir="$BUILD_ROOT/kwin"
    clone_at https://gitlab.archlinux.org/archlinux/packaging/packages/kwin.git "$KWINKG" "$dir"
    sed -i "s/^arch=(.*)$/arch=('aarch64')/" "$dir/PKGBUILD"
    cp "$SCRIPT_DIR/anland-kwin/kwin.patch" "$dir/anland-kwin.patch"
    cp -a "$SCRIPT_DIR/anland-kwin/backend" "$dir/anland-backend"
    cat >> "$dir/PKGBUILD" <<'EOF_KWIN_PATCH'
source+=(anland-kwin.patch)
sha256sums+=('SKIP')

prepare() {
  cd "$srcdir/kwin-$pkgver"
  patch -Np1 -i "$srcdir/anland-kwin.patch"
  mkdir -p src/backends/anland
  cp -a "$startdir/anland-backend/." src/backends/anland/
}
EOF_KWIN_PATCH
    chown -R user:user "$dir"
    su user -c "cd '$dir' && makepkg --syncdeps --noconfirm --nocheck --skippgpcheck --cleanbuild --clean"
    pacman -U --noconfirm "$dir"/kwin-*.pkg.tar.zst
}

build_xwayland() {
    local dir="$BUILD_ROOT/xorg-xwayland"
    clone_at https://gitlab.archlinux.org/archlinux/packaging/packages/xorg-xwayland.git "$XWAYLANDKG" "$dir"
    sed -i "s/^arch=(.*)$/arch=('aarch64')/" "$dir/PKGBUILD"
    cp "$SCRIPT_DIR/anland-kwin/xwayland.patch" "$dir/anland-xwayland.patch"
    cat >> "$dir/PKGBUILD" <<'EOF_XWAYLAND_PATCH'
source+=(anland-xwayland.patch)
sha512sums+=('SKIP')

prepare() {
  cd "$srcdir/xwayland-$pkgver"
  patch -Np1 -i "$srcdir/anland-xwayland.patch"
}
EOF_XWAYLAND_PATCH
    chown -R user:user "$dir"
    su user -c "cd '$dir' && makepkg --syncdeps --noconfirm --nocheck --skippgpcheck --cleanbuild --clean"
    pacman -U --noconfirm "$dir"/xorg-xwayland-*.pkg.tar.zst
}

build_kwin
build_xwayland
printf '%s\n' 'patched-kwin=arch-native-6.7.3-anland' > /usr/share/droidspaces/anland-kwin-package
