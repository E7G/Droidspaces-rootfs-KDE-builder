#!/usr/bin/env bash
set -euo pipefail

source /etc/droidspaces-desktop.conf
[[ -r /etc/droidspaces-device.conf ]] && source /etc/droidspaces-device.conf

case "${DESKTOP:-none}:${DISPLAY_BACKEND:-x11}" in
    none:x11)
        exit 0
        ;;
    kde:x11)
        export DISPLAY="${DISPLAY:-:5}"
        exec startplasma-x11
        ;;
    kde:anland-wayland)
        # Clover/kernel-4.4 needs the compatibility session wrapper. Generic
        # devices stay on the normal Plasma entry point.
        if [[ "${DEVICE_PROFILE:-generic}" == "mi-pad4-clover" ]] && \
           command -v mi-pad4-start-wayland >/dev/null 2>&1; then
            exec mi-pad4-start-wayland child
        fi
        exec startplasma-wayland
        ;;
    kde-mobile:anland-wayland)
        exec startplasmamobile
        ;;
    *)
        echo "unsupported desktop session: ${DESKTOP:-}/${DISPLAY_BACKEND:-}" >&2
        exit 1
        ;;
esac
