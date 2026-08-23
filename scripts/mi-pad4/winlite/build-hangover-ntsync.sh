#!/usr/bin/bash

set -euo pipefail

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

bundle="$BUNDLE_DIR/hangover_${HANGOVER_VERSION}_ubuntu2404_noble_arm64.tar"
curl -fL --retry 5 --retry-all-errors \
    -o "$bundle" \
    "https://github.com/AndreRH/hangover/releases/download/hangover-${HANGOVER_VERSION}/hangover_${HANGOVER_VERSION}_ubuntu2404_noble_arm64.tar"
echo "${HANGOVER_SHA256}  $bundle" | sha256sum -c -
tar -xf "$bundle" -C "$BUNDLE_DIR"

# Pin the exact upstream release source. Hangover 11.9 points at this Wine
# commit; fail rather than silently building a different Wine revision.
git clone --depth 1 --branch "hangover-${HANGOVER_VERSION}" \
    https://github.com/AndreRH/hangover.git "$SOURCE_DIR"
git -C "$SOURCE_DIR" submodule update --init --depth 1 wine
actual_wine_commit="$(git -C "$SOURCE_DIR/wine" rev-parse HEAD)"
if [[ "$actual_wine_commit" != "$HANGOVER_WINE_COMMIT" ]]; then
    echo "Hangover ${HANGOVER_VERSION} Wine commit changed: $actual_wine_commit" >&2
    exit 1
fi

# Official 11.9 gates NTSync on HAVE_LINUX_NTSYNC_H. Android kernels may expose
# /dev/ntsync while the Ubuntu cross-build headers do not contain that header.
# Carry the small UAPI locally, then inject it into the packaging image as the
# system <linux/ntsync.h> before configure runs. This keeps Wine's upstream
# feature detection and source guards intact instead of teaching makedep about
# a private Wine header.
git -C "$SOURCE_DIR/wine" apply "$PATCH_FILE"
grep -Fq '<linux/ntsync.h>' "$SOURCE_DIR/wine/server/inproc_sync.c"
grep -Fq '<linux/ntsync.h>' "$SOURCE_DIR/wine/dlls/ntdll/unix/sync.c"
grep -Fq 'NTSYNC_IOC_CREATE_EVENT' "$SOURCE_DIR/wine/include/wine/ntsync.h"

# Use Hangover's own Noble cross-package recipe so ARM64EC behavior and paths
# stay compatible with the upstream 11.9 FEX / wowbox64 payloads.
cp -a "$SOURCE_DIR/.packaging/ubuntu2404/wine/." "$SOURCE_DIR/wine/"
sed -i "s/HOVERSION/${HANGOVER_VERSION}/g" "$SOURCE_DIR/wine/Dockerfile"
sed -i '/^ENV PATH=/a COPY include/wine/ntsync.h /usr/include/linux/ntsync.h' \
    "$SOURCE_DIR/wine/Dockerfile"
grep -Fq 'COPY include/wine/ntsync.h /usr/include/linux/ntsync.h' \
    "$SOURCE_DIR/wine/Dockerfile"

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

docker build -t foundationubuntu2404 "$SOURCE_DIR/.packaging/ubuntu2404"
docker build -t hangover-wine-winlite-ntsync "$SOURCE_DIR/wine"

wine_deb="$BUNDLE_DIR/hangover-wine_${HANGOVER_VERSION}~noble_arm64.deb"
docker run --rm hangover-wine-winlite-ntsync \
    cat "/opt/hangover-wine_${HANGOVER_VERSION}~noble_arm64.deb" \
    >"$wine_deb"
test -s "$wine_deb"

shopt -s nullglob
fex_debs=("$BUNDLE_DIR"/hangover-libarm64ecfex_*_arm64.deb)
box_debs=("$BUNDLE_DIR"/hangover-wowbox64_*_arm64.deb)
((${#fex_debs[@]} == 1))
((${#box_debs[@]} == 1))
debs=("$wine_deb" "${fex_debs[0]}" "${box_debs[0]}")

for deb in "${debs[@]}"; do
    member="$(ar t "$deb" | grep '^data\.tar' | head -n1)"
    [[ -n "$member" ]]
    case "$member" in
        *.zst) ar p "$deb" "$member" | tar --zstd -x -C "$ROOTFS" ;;
        *.xz)  ar p "$deb" "$member" | tar -xJ -C "$ROOTFS" ;;
        *.gz)  ar p "$deb" "$member" | tar -xz -C "$ROOTFS" ;;
        *)     ar p "$deb" "$member" | tar -x -C "$ROOTFS" ;;
    esac
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

# Do not trust package names alone: the custom wineserver must literally carry
# the /dev/ntsync path, proving inproc_sync.c was compiled into the binary.
test -x "$ROOTFS/usr/bin/wine"
test -x "$ROOTFS/usr/bin/wineserver"
grep -aFq '/dev/ntsync' "$ROOTFS/usr/bin/wineserver"
find "$ROOTFS/usr/lib" -name libarm64ecfex.dll -print -quit | grep -q .
find "$ROOTFS/usr/lib" -name wowbox64.dll -print -quit | grep -q .

echo "WinLite Hangover ${HANGOVER_VERSION} NTSync runtime built successfully"
