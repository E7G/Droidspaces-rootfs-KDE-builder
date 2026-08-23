#!/usr/bin/bash

set -Eeuo pipefail

stage="startup"
trap 'rc=$?; echo "::error::Hangover WinLite failed during ${stage}: ${BASH_COMMAND} (exit ${rc})" >&2; exit "$rc"' ERR

HANGOVER_VERSION="${HANGOVER_VERSION:-11.9}"
HANGOVER_SHA256="${HANGOVER_SHA256:-0c66e48800c03d32c3c22029b5053cef3d61376aedcf44eaddf82dce63e410dd}"
HANGOVER_WINE_COMMIT="${HANGOVER_WINE_COMMIT:-2e8ad15d5b7b87ef0e1520bf9fec2ecfb31fd1b1}"
OUTPUT_DIR="${1:-hangover-winlite}"
ROOTFS="$OUTPUT_DIR/rootfs"
WORK_DIR="${HANGOVER_WORK_DIR:-.ci/hangover-ntsync}"
SOURCE_DIR="$WORK_DIR/source"
BUNDLE_DIR="$WORK_DIR/bundle"
PATCH_FILE="$(cd "$(dirname "$0")" && pwd)/hangover-11.9-android-ntsync.patch"

rm -rf "$WORK_DIR" "$OUTPUT_DIR"
mkdir -p "$BUNDLE_DIR" "$ROOTFS"

stage="download official Hangover bundle"
bundle="$BUNDLE_DIR/hangover_${HANGOVER_VERSION}_ubuntu2404_noble_arm64.tar"
curl -fL --retry 5 --retry-all-errors \
    -o "$bundle" \
    "https://github.com/AndreRH/hangover/releases/download/hangover-${HANGOVER_VERSION}/hangover_${HANGOVER_VERSION}_ubuntu2404_noble_arm64.tar"
echo "${HANGOVER_SHA256}  $bundle" | sha256sum -c -
tar -xf "$bundle" -C "$BUNDLE_DIR"

# Pin the exact upstream release source. Hangover 11.9 points at this Wine
# commit; fail rather than silently building a different Wine revision.
stage="prepare pinned Hangover source"
git clone --depth 1 --branch "hangover-${HANGOVER_VERSION}" \
    https://github.com/AndreRH/hangover.git "$SOURCE_DIR"
git -C "$SOURCE_DIR" submodule update --init --depth 1 wine
actual_wine_commit="$(git -C "$SOURCE_DIR/wine" rev-parse HEAD)"
if [[ "$actual_wine_commit" != "$HANGOVER_WINE_COMMIT" ]]; then
    echo "Hangover ${HANGOVER_VERSION} Wine commit changed: $actual_wine_commit" >&2
    exit 1
fi

# Official 11.9 gates NTSync on HAVE_LINUX_NTSYNC_H. Android kernels may expose
# /dev/ntsync while Ubuntu Noble's ARM64 cross headers do not contain that UAPI.
# Carry the small UAPI locally; it is injected into the actual aarch64-linux-gnu
# sysroot below before Wine's cross configure runs.
stage="apply Android NTSync UAPI"
git -C "$SOURCE_DIR/wine" apply "$PATCH_FILE"
grep -Fq '<linux/ntsync.h>' "$SOURCE_DIR/wine/server/inproc_sync.c"
grep -Fq '<linux/ntsync.h>' "$SOURCE_DIR/wine/dlls/ntdll/unix/sync.c"
grep -Fq 'NTSYNC_IOC_CREATE_EVENT' "$SOURCE_DIR/wine/include/wine/ntsync.h"

# Use Hangover's own Noble cross-package recipe so ARM64EC behavior and paths
# stay compatible with the upstream 11.9 FEX / wowbox64 payloads.
stage="prepare Hangover Noble packaging"
cp -a "$SOURCE_DIR/.packaging/ubuntu2404/wine/." "$SOURCE_DIR/wine/"
sed -i "s/HOVERSION/${HANGOVER_VERSION}/g" "$SOURCE_DIR/wine/Dockerfile"

# dpkg-buildpackage -a arm64 configures Wine with CC=aarch64-linux-gnu-gcc.
# Putting ntsync.h only in /usr/include is insufficient for that cross compiler:
# its libc-dev-arm64-cross sysroot is /usr/aarch64-linux-gnu/include. Install the
# UAPI there as well, prove that the target compiler can consume it, then seed
# Autoconf's header result so the server/ntdll NTSync code cannot be compiled out.
sed -i '/^ENV PATH=/a ENV ac_cv_header_linux_ntsync_h=yes\
COPY include/wine/ntsync.h /tmp/winlite-ntsync.h\
RUN install -Dm644 /tmp/winlite-ntsync.h /usr/aarch64-linux-gnu/include/linux/ntsync.h \\\n    && install -Dm644 /tmp/winlite-ntsync.h /usr/include/linux/ntsync.h \\\n    && printf '\''#include <linux/ntsync.h>\\n#ifndef NTSYNC_IOC_EVENT_READ\\n#error NTSync UAPI incomplete\\n#endif\\nint main(void){return 0;}\\n'\'' \\\n       | aarch64-linux-gnu-gcc -x c -c -o /tmp/winlite-ntsync-test.o - \\\n    && rm -f /tmp/winlite-ntsync-test.o /tmp/winlite-ntsync.h' \
    "$SOURCE_DIR/wine/Dockerfile"

grep -Fq 'ac_cv_header_linux_ntsync_h=yes' "$SOURCE_DIR/wine/Dockerfile"
grep -Fq '/usr/aarch64-linux-gnu/include/linux/ntsync.h' "$SOURCE_DIR/wine/Dockerfile"

changelog="$SOURCE_DIR/wine/debian/changelog"
cp "$changelog" "$changelog.old"
{
    echo "hangover-wine (${HANGOVER_VERSION}~noble) UNRELEASED; urgency=low"
    echo
    echo "  * WinLite Android NTSync build"
    echo
    printf ' -- WinLite Builder <noreply@localhost>  '
    LC_ALL=C date -R
    echo
    cat "$changelog.old"
} >"$changelog"
rm -f "$changelog.old"

stage="build Hangover foundation image"
docker build -t foundationubuntu2404 "$SOURCE_DIR/.packaging/ubuntu2404"
stage="build patched Hangover Wine image"
docker build -t hangover-wine-winlite-ntsync "$SOURCE_DIR/wine"

# Do not assume the exact output path after a long cross-build. Discover the
# generated arm64 package in the image, print what was found, then export it.
# This also makes any post-build failure visible in Actions instead of ending
# with a bare exit code after BuildKit reports success.
stage="export patched Hangover Wine package"
command -v dpkg-deb >/dev/null
image_wine_deb="$(docker run --rm hangover-wine-winlite-ntsync sh -lc \
    'find /opt -maxdepth 1 -type f -name "hangover-wine_*_arm64.deb" -print -quit')"
if [[ -z "$image_wine_deb" ]]; then
    echo "No hangover-wine arm64 .deb was produced by the build image" >&2
    docker run --rm hangover-wine-winlite-ntsync sh -lc \
        'find /opt -maxdepth 2 -type f -name "*.deb" -print | sort' >&2 || true
    exit 1
fi
printf 'custom-wine-package=%s\n' "$image_wine_deb"

wine_deb="$BUNDLE_DIR/hangover-wine_${HANGOVER_VERSION}~noble_arm64.deb"
docker run --rm hangover-wine-winlite-ntsync sh -c 'cat "$1"' sh "$image_wine_deb" \
    >"$wine_deb"
test -s "$wine_deb"
printf 'exported-wine-package='; dpkg-deb -f "$wine_deb" Package Version Architecture | paste -sd' ' -

# The upstream release bundle is flat today, but use find instead of a shell
# glob so a harmless archive directory layout change does not break WinLite.
stage="locate Hangover emulator packages"
mapfile -t fex_debs < <(find "$BUNDLE_DIR" -maxdepth 3 -type f \
    -name 'hangover-libarm64ecfex_*_arm64.deb' -print | sort)
mapfile -t box_debs < <(find "$BUNDLE_DIR" -maxdepth 3 -type f \
    -name 'hangover-wowbox64_*_arm64.deb' -print | sort)
if ((${#fex_debs[@]} != 1 || ${#box_debs[@]} != 1)); then
    printf 'Expected one ARM64EC FEX and one wowbox64 package; found fex=%d box=%d\n' \
        "${#fex_debs[@]}" "${#box_debs[@]}" >&2
    find "$BUNDLE_DIR" -maxdepth 3 -type f -name '*.deb' -print | sort >&2
    exit 1
fi
printf 'fex-package=%s\nbox-package=%s\n' "${fex_debs[0]}" "${box_debs[0]}"
debs=("$wine_deb" "${fex_debs[0]}" "${box_debs[0]}")

# Let dpkg-deb handle data.tar.{xz,zst,gz,...}; hand-parsing the ar member is
# unnecessary and was another silent failure point after the expensive build.
stage="extract Hangover runtime packages"
for deb in "${debs[@]}"; do
    printf 'extracting='; dpkg-deb -f "$deb" Package Version Architecture | paste -sd' ' -
    dpkg-deb -x "$deb" "$ROOTFS"
done

rm -rf \
    "$ROOTFS/usr/share/doc" \
    "$ROOTFS/usr/share/man" \
    "$ROOTFS/usr/lib/debug"
install -d "$ROOTFS/usr/share"
printf '%s\n' \
    "hangover=${HANGOVER_VERSION}-winlite-ntsync" \
    "wine-base=${HANGOVER_WINE_COMMIT}" \
    'ntsync=compiled-in-android-uapi' \
    'ntsync-device=/dev/ntsync' \
    'ntsync-runtime=auto' \
    'ntsync-fallback=esync' \
    'x64=arm64ec-fex' \
    'x86=wowbox64' \
    >"$ROOTFS/usr/share/hangover-winlite-version"

# This is a functional check, not a version pin. The literal lives only in the
# NTSync implementation guarded by HAVE_LINUX_NTSYNC_H/NTSYNC_IOC_EVENT_READ,
# so its presence proves the target server actually contains the code path.
stage="validate extracted Hangover runtime"
ls -l "$ROOTFS/usr/bin/wine" "$ROOTFS/usr/bin/wineserver"
test -x "$ROOTFS/usr/bin/wine"
test -x "$ROOTFS/usr/bin/wineserver"
if ! grep -aFq '/dev/ntsync' "$ROOTFS/usr/bin/wineserver"; then
    echo "Patched wineserver does not contain /dev/ntsync; NTSync was not compiled in" >&2
    exit 1
fi
fex_dll="$(find "$ROOTFS/usr/lib" -name libarm64ecfex.dll -print -quit)"
box_dll="$(find "$ROOTFS/usr/lib" -name wowbox64.dll -print -quit)"
[[ -n "$fex_dll" ]]
[[ -n "$box_dll" ]]
printf 'fex-dll=%s\nbox-dll=%s\n' "$fex_dll" "$box_dll"

echo "WinLite Hangover ${HANGOVER_VERSION} NTSync runtime built successfully"
