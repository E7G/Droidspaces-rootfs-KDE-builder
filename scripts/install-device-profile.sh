#!/usr/bin/env bash
set -euo pipefail

profile="${1:-generic}"
profile_dir="${DROIDSPACES_DEVICE_PROFILE_DIR:-/usr/local/lib/droidspaces/device-profiles}"

case "$profile" in
    generic|mi-pad4-clover) ;;
    *)
        echo "unsupported device profile: $profile" >&2
        exit 1
        ;;
esac

script="$profile_dir/$profile.sh"
[[ -x "$script" ]] || { echo "missing device profile: $script" >&2; exit 1; }
exec "$script" install
