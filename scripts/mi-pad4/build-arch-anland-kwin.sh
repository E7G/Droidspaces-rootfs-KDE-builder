#!/bin/bash
set -euo pipefail

# Build Anland KWin/Xwayland with Arch's own Qt/ABI. Fedora RPM payloads must
# not be copied into Arch: they link against Fedora's private Qt ABI.

case "${BUILD_KDE:-}" in
    min|conc) ;;
    *) exit 0 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT=/tmp/droidspaces-arch-anland-build
PACKAGE_OUTPUT_DIR="${ANLAND_PACKAGE_OUTPUT_DIR:-}"
KIOKG=97c0d35b1b7e526eef330747e9bf28e6da31f430
KWINKG=365ae0acc5f521f53a85fe6d9a030646687324f8
XWAYLANDKG=8f82d79d312192108bb6417187c6ea986cdfcb3c
PLASMAWORKSPACEKG=864d8e5f78cb3665317efc5ca3f525e87a30f6dc

# Normal RootFS keeps the complete Plasma screen-locker stack. The dedicated
# WinLite package builder intentionally disables it because WinLite has no
# logind/ConsoleKit session manager and cannot safely recover from a lock.
# SCREENLOCKER_MODE can be set explicitly to keep/disable. Auto mode identifies
# the existing WinLite KWin-only artifact build without changing other callers.
SCREENLOCKER_MODE="${SCREENLOCKER_MODE:-auto}"
if [[ "$SCREENLOCKER_MODE" == auto ]]; then
    if [[ "${BUILD_KIO:-true}" == true \
          && "${BUILD_XWAYLAND:-true}" == false \
          && "${BUILD_PLASMA_WORKSPACE:-true}" == false \
          && -n "$PACKAGE_OUTPUT_DIR" ]]; then
        SCREENLOCKER_MODE=disable
    else
        SCREENLOCKER_MODE=keep
    fi
fi
case "$SCREENLOCKER_MODE" in
    keep|disable) ;;
    *) echo "Invalid SCREENLOCKER_MODE=$SCREENLOCKER_MODE (expected keep or disable)" >&2; exit 1 ;;
esac

pacman -S --noconfirm --needed \
    base-devel cmake ninja meson extra-cmake-modules kdoctools krunner \
    plasma-wayland-protocols python qt6-tools vulkan-headers wayland-protocols \
    xorgproto xtrans xorg-font-util xorg-xwayland libcap

install -d -m 0755 /etc/sudoers.d
printf '%s\n' 'user ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/droidspaces-user
chmod 0440 /etc/sudoers.d/droidspaces-user

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT"

# Arch/Mi Pad uses the repository's Clover/KGSL-specialized backend.
# It carries the V2 window/scheduling protocol while preserving the surfaceless
# EGL and legacy KGSL paths required by this Arch target.
ANLAND_ARCH_BACKEND_DIR="$SCRIPT_DIR/anland-kwin/backend"
test -f "$ANLAND_ARCH_BACKEND_DIR/anland_backend.cpp"
test -f "$ANLAND_ARCH_BACKEND_DIR/anland_egl_backend.cpp"
test -f "$ANLAND_ARCH_BACKEND_DIR/protocol.h"
ANLAND_ARCH_BACKEND_REV="$(
    find "$ANLAND_ARCH_BACKEND_DIR" -maxdepth 1 -type f -print0 |
        sort -z |
        xargs -0 sha256sum |
        sha256sum |
        awk '{print $1}'
)"
echo "Using specialized Arch/Clover Anland backend $ANLAND_ARCH_BACKEND_REV"

# Arch's current pacman defaults require signatures for local files. Packages
# produced by this CI build are intentionally unsigned; relax checking only in
# this temporary install config, never in the final rootfs configuration.
PACMAN_LOCAL_CONFIG="$BUILD_ROOT/pacman-localpkg.conf"
cp /etc/pacman.conf "$PACMAN_LOCAL_CONFIG"
if grep -Eq '^[[:space:]]*LocalFileSigLevel[[:space:]]*=' "$PACMAN_LOCAL_CONFIG"; then
    sed -i 's/^[[:space:]]*LocalFileSigLevel[[:space:]]*=.*/LocalFileSigLevel = Never/' "$PACMAN_LOCAL_CONFIG"
else
    sed -i '/^\[options\]/a LocalFileSigLevel = Never' "$PACMAN_LOCAL_CONFIG"
fi

install_local_package() {
    pacman --config "$PACMAN_LOCAL_CONFIG" -U --noconfirm "$1"
}

clone_at() {
    local url="$1" commit="$2" dir="$3"
    git clone --filter=blob:none --no-checkout "$url" "$dir"
    git -C "$dir" fetch --depth=1 origin "$commit"
    git -C "$dir" checkout --detach "$commit"
}

download_with_fallback() {
    local output="$1"
    shift
    local url tmp="${output}.part"

    rm -f "$output" "$tmp"
    for url in "$@"; do
        echo "Downloading $(basename "$output") from $url"
        if curl -4 -fL \
            --connect-timeout 30 \
            --max-time 180 \
            --retry 4 \
            --retry-all-errors \
            --retry-delay 3 \
            -o "$tmp" "$url"; then
            mv "$tmp" "$output"
            return 0
        fi
        rm -f "$tmp"
        echo "Download failed, trying next X.Org mirror" >&2
    done

    echo "All download mirrors failed for $(basename "$output")" >&2
    return 1
}

prefetch_xwayland_sources() {
    local dir="$1" pkgver filename suffix base
    local -a mirrors urls

    pkgver="$(sed -n 's/^pkgver=//p' "$dir/PKGBUILD" | head -n1 | tr -d "'\"")"
    [[ -n "$pkgver" ]] || {
        echo 'Unable to determine xorg-xwayland pkgver' >&2
        return 1
    }

    # Prefer X.Org's canonical release directory, then fall back to independent
    # mirrors known to carry individual/xserver releases. Some mirrors can lag
    # behind a new security release, so never make one mirror a hard dependency.
    # Pre-fetching into makepkg's default SRCDEST preserves Arch's normal
    # checksum/PGP validation.
    mirrors=(
        'https://xorg.freedesktop.org/releases/individual/xserver/'
        'https://artfiles.org/x.org/pub/individual/xserver/'
        'https://ftp.gwdg.de/pub/x11/x.org/pub/individual/xserver/'
        'https://mirror.csclub.uwaterloo.ca/x.org/individual/xserver/'
        'https://ftp.yz.yamagata-u.ac.jp/pub/X11/x.org/individual/xserver/'
        'https://mirrors.ircam.fr/pub/x.org/individual/xserver/'
        'https://www.mirrorservice.org/sites/ftp.x.org/pub/individual/xserver/'
    )

    for suffix in '' '.sig'; do
        filename="xwayland-${pkgver}.tar.xz${suffix}"
        urls=()
        for base in "${mirrors[@]}"; do
            urls+=("${base}${filename}")
        done
        download_with_fallback "$dir/$filename" "${urls[@]}"
    done
}

build_kio() {
    local dir="$BUILD_ROOT/kio"
    clone_at https://gitlab.archlinux.org/archlinux/packaging/packages/kio.git "$KIOKG" "$dir"
    sed -i "s/^arch=(.*)$/arch=('aarch64')/" "$dir/PKGBUILD"
    cp "$SCRIPT_DIR/kio-runtime-named-socket.patch" "$dir/kio-runtime-named-socket.patch"
    cat >> "$dir/PKGBUILD" <<'EOF_KIO_PATCH'
source+=(kio-runtime-named-socket.patch)
sha256sums+=('SKIP')

prepare() {
  cd "$srcdir/kio-$pkgver"
  patch -Np1 -i "$srcdir/kio-runtime-named-socket.patch"
}
EOF_KIO_PATCH
    mkdir -p "$BUILD_ROOT/packages"
    chown -R user:user "$BUILD_ROOT/packages"
    chown -R user:user "$dir"
    su user -c "cd '$dir' && PKGDEST='$BUILD_ROOT/packages' makepkg --syncdeps --noconfirm --nocheck --skippgpcheck --cleanbuild --clean"
    local package
    package="$(find "$BUILD_ROOT/packages" -maxdepth 1 -type f -name 'kio-[0-9]*.pkg.tar.*' -print -quit)"
    [ -n "$package" ] || { echo 'kio package was not produced' >&2; find "$BUILD_ROOT" -maxdepth 3 -type f -name '*.pkg.tar.*' >&2; exit 1; }
    install_local_package "$package"
    install -d -m 0755 /usr/share/droidspaces
    printf '%s\n' 'patched-kio=named-worker-socket-for-kernel-4.4' \
        > /usr/share/droidspaces/kio-runtime-named-socket
}

build_kwin() {
    local dir="$BUILD_ROOT/kwin"
    clone_at https://gitlab.archlinux.org/archlinux/packaging/packages/kwin.git "$KWINKG" "$dir"
    sed -i "s/^arch=(.*)$/arch=('aarch64')/" "$dir/PKGBUILD"

    if [[ "$SCREENLOCKER_MODE" == disable ]]; then
        # WinLite must not carry a hard dependency on KScreenLocker.
        sed -Ei "/^[[:space:]]*['\"]?kscreenlocker['\"]?[[:space:]]*$/d" "$dir/PKGBUILD"
    fi

    cp "$SCRIPT_DIR/anland-kwin/kwin.patch" "$dir/anland-kwin.patch"
    cp -a "$ANLAND_ARCH_BACKEND_DIR" "$dir/anland-backend"
    if [[ "$SCREENLOCKER_MODE" == disable ]]; then
        cat >> "$dir/PKGBUILD" <<'EOF_KWIN_PATCH_NO_LOCKER'
source+=(anland-kwin.patch)
sha256sums+=('SKIP')

prepare() {
  cd "$srcdir/kwin-$pkgver"
  patch -Np1 -i "$srcdir/anland-kwin.patch"
  mkdir -p src/backends/anland
  cp -a "$startdir/anland-backend/." src/backends/anland/

  # WinLite has no usable session locker. Compile the integration completely out.
  sed -i 's/^\(option(KWIN_BUILD_SCREENLOCKER .* \)ON)$/\1OFF)/' CMakeLists.txt
  grep -Eq '^option\(KWIN_BUILD_SCREENLOCKER .* OFF\)$' CMakeLists.txt
}
EOF_KWIN_PATCH_NO_LOCKER
    else
        cat >> "$dir/PKGBUILD" <<'EOF_KWIN_PATCH_WITH_LOCKER'
source+=(anland-kwin.patch)
sha256sums+=('SKIP')

prepare() {
  cd "$srcdir/kwin-$pkgver"
  patch -Np1 -i "$srcdir/anland-kwin.patch"
  mkdir -p src/backends/anland
  cp -a "$startdir/anland-backend/." src/backends/anland/

  # Normal RootFS keeps the standard KScreenLocker integration enabled.
  grep -Eq '^option\(KWIN_BUILD_SCREENLOCKER .* ON\)$' CMakeLists.txt
}
EOF_KWIN_PATCH_WITH_LOCKER
    fi

    mkdir -p "$BUILD_ROOT/packages"
    chown -R user:user "$BUILD_ROOT/packages"
    chown -R user:user "$dir"
    su user -c "cd '$dir' && PKGDEST='$BUILD_ROOT/packages' makepkg --syncdeps --noconfirm --nocheck --skippgpcheck --cleanbuild --clean"
    local package
    package="$(find "$BUILD_ROOT/packages" -maxdepth 1 -type f -name 'kwin-*.pkg.tar.*' -print -quit)"
    [ -n "$package" ] || { echo 'kwin package was not produced' >&2; find "$BUILD_ROOT" -maxdepth 3 -type f -name '*.pkg.tar.*' >&2; exit 1; }

    if [[ "$SCREENLOCKER_MODE" == disable ]]; then
        if bsdtar -xOf "$package" .PKGINFO | grep -Eq '^depend = kscreenlocker([<>=].*)?$'; then
            echo 'WinLite KWin package still depends on kscreenlocker' >&2
            exit 1
        fi
    else
        if ! bsdtar -xOf "$package" .PKGINFO | grep -Eq '^depend = kscreenlocker([<>=].*)?$'; then
            echo 'Normal RootFS KWin package unexpectedly lost its kscreenlocker dependency' >&2
            exit 1
        fi
    fi

    install_local_package "$package"
    if [[ "$SCREENLOCKER_MODE" == keep ]] && ! pacman -Q kscreenlocker >/dev/null 2>&1; then
        echo 'Normal RootFS must retain kscreenlocker' >&2
        exit 1
    fi
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
    prefetch_xwayland_sources "$dir"
    mkdir -p "$BUILD_ROOT/packages"
    chown -R user:user "$BUILD_ROOT/packages"
    chown -R user:user "$dir"
    su user -c "cd '$dir' && PKGDEST='$BUILD_ROOT/packages' makepkg --syncdeps --noconfirm --nocheck --skippgpcheck --cleanbuild --clean"
    local package
    package="$(find "$BUILD_ROOT/packages" -maxdepth 1 -type f -name 'xorg-xwayland-*.pkg.tar.*' -print -quit)"
    [ -n "$package" ] || { echo 'xorg-xwayland package was not produced' >&2; find "$BUILD_ROOT" -maxdepth 3 -type f -name '*.pkg.tar.*' >&2; exit 1; }
    install_local_package "$package"
}

build_plasma_workspace() {
    local dir="$BUILD_ROOT/plasma-workspace"
    clone_at https://gitlab.archlinux.org/archlinux/packaging/packages/plasma-workspace.git "$PLASMAWORKSPACEKG" "$dir"
    sed -i "s/^arch=(.*)$/arch=('aarch64')/" "$dir/PKGBUILD"
    cp "$SCRIPT_DIR/plasma-workspace-panel-remap.patch" "$dir/mi-pad4-panel-remap.patch"
    cat >> "$dir/PKGBUILD" <<'EOF_PLASMA_WORKSPACE_PATCH'
source+=(mi-pad4-panel-remap.patch)
sha256sums+=('SKIP')

prepare() {
  cd "$srcdir/plasma-workspace-$pkgver"
  patch -Np1 -i "$srcdir/mi-pad4-panel-remap.patch"
}
EOF_PLASMA_WORKSPACE_PATCH
    mkdir -p "$BUILD_ROOT/packages"
    chown -R user:user "$BUILD_ROOT/packages"
    chown -R user:user "$dir"
    su user -c "cd '$dir' && PKGDEST='$BUILD_ROOT/packages' makepkg --syncdeps --noconfirm --nocheck --skippgpcheck --cleanbuild --clean"
    local package
    package="$(find "$BUILD_ROOT/packages" -maxdepth 1 -type f -name 'plasma-workspace-[0-9]*.pkg.tar.*' -print -quit)"
    [ -n "$package" ] || { echo 'plasma-workspace package was not produced' >&2; find "$BUILD_ROOT" -maxdepth 3 -type f -name '*.pkg.tar.*' >&2; exit 1; }
    install_local_package "$package"
}

if [[ "${BUILD_KIO:-true}" = true ]]; then
    build_kio
elif [[ ! -f /usr/share/droidspaces/kio-runtime-named-socket ]]; then
    echo 'BUILD_KIO=false but the patched KIO package is not installed' >&2
    exit 1
fi
if [[ "${BUILD_KWIN:-true}" = true ]]; then
    build_kwin
fi
if [[ "${BUILD_XWAYLAND:-true}" = true ]]; then
    build_xwayland
fi
if [[ "${BUILD_PLASMA_WORKSPACE:-true}" = true ]]; then
    build_plasma_workspace
fi
if [[ -n "$PACKAGE_OUTPUT_DIR" ]]; then
    mkdir -p "$PACKAGE_OUTPUT_DIR"
    cp -a "$BUILD_ROOT/packages"/*.pkg.tar.* "$PACKAGE_OUTPUT_DIR/"
fi
install -d -m 0755 /usr/share/droidspaces
if [[ "$SCREENLOCKER_MODE" == disable ]]; then
    screenlocker_status='disabled-for-winlite'
else
    screenlocker_status='enabled-and-retained'
fi
printf '%s\n' \
  'patched-kwin=arch-native-6.7.3-anland' \
  "anland-arch-backend=${ANLAND_ARCH_BACKEND_REV}" \
  'anland-source=rootfs-specialized-clover-kgsl' \
  'droidspaces-mode=wslg-v2-compatible' \
  "screenlocker=${screenlocker_status}" \
  'socket=/run/display.sock' \
  > /usr/share/droidspaces/anland-kwin-package
printf '%s\n' 'patched-plasma-workspace=6.7.4-anland-panel-remap' > /usr/share/droidspaces/plasma-workspace-panel-remap
