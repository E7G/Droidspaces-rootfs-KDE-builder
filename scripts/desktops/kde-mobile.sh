#!/usr/bin/env bash
set -euo pipefail

base="${DROIDSPACES_DESKTOP_PROFILE_DIR:-/usr/local/lib/droidspaces/desktops}/kde.sh"
[[ -x "$base" ]] || { echo "missing KDE base profile: $base" >&2; exit 1; }

case "${1:-install}" in
    install)
        "$base" install
        pacman -S --noconfirm --needed plasma-mobile plasma-keyboard
        ;;
    configure-environment)
        "$base" configure-environment "${2:-anland-wayland}"
        ;;
    *)
        echo "invalid KDE mobile profile action: ${1:-}" >&2
        exit 1
        ;;
esac
