#!/usr/bin/env bash
set -euo pipefail

desktop="${1:-none}"
profile_dir="${DROIDSPACES_DESKTOP_PROFILE_DIR:-/usr/local/lib/droidspaces/desktops}"

case "$desktop" in
    none)
        echo "--> desktop profile: none"
        exit 0
        ;;
    kde|kde-mobile) ;;
    *)
        echo "unsupported desktop profile: $desktop" >&2
        exit 1
        ;;
esac

profile="$profile_dir/$desktop.sh"
[[ -x "$profile" ]] || { echo "missing desktop profile: $profile" >&2; exit 1; }
exec "$profile" install
