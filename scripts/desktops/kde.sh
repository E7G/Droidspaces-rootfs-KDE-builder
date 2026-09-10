#!/usr/bin/env bash
set -euo pipefail

configure_environment() {
    local backend="${1:-x11}"
    local envfile="/etc/environment"
    touch "$envfile"
    grep -q '^XCURSOR_SIZE=' "$envfile" || echo 'XCURSOR_SIZE=48' >> "$envfile"

    case "$backend" in
        x11)
            grep -q '^DISPLAY=' "$envfile" || echo 'DISPLAY=:5' >> "$envfile"
            ;;
        anland-wayland)
            grep -q '^ANLAND=' "$envfile" || echo 'ANLAND=1' >> "$envfile"
            grep -q '^ANLAND_SOCKET=' "$envfile" || echo 'ANLAND_SOCKET=/run/display.sock' >> "$envfile"
            grep -q '^ANLAND_SKIP_IMPLICIT_SYNC_WAIT=' "$envfile" || echo 'ANLAND_SKIP_IMPLICIT_SYNC_WAIT=1' >> "$envfile"
            # Deliberately do not force QT_QPA_PLATFORM or WAYLAND_DISPLAY.
            # Linux Apps gets a fresh compositor/session and XWayland fallback.
            ;;
        *)
            echo "invalid KDE backend: $backend" >&2
            return 1
            ;;
    esac
}

install_profile() {
    pacman -S --noconfirm --needed \
        xorg-xrandr xorg-server xorg-xwayland xkeyboard-config \
        noto-fonts-cjk noto-fonts-emoji \
        plasma-desktop plasma-workspace pipewire pipewire-alsa pipewire-pulse wireplumber \
        powerdevil kscreen plasma-pa ark kwin kwin-x11 upower konsole dolphin kate \
        kinfocenter mesa-utils libpulse vulkan-tools wayland-utils \
        kfind plasma-systemmonitor filelight systemsettings kscreenlocker kio-extras \
        xdg-user-dirs dolphin-plugins ffmpegthumbs kdegraphics-thumbnailers kimageformats \
        plasma-browser-integration libcanberra gstreamer gst-plugins-base gst-plugins-good \
        sound-theme-freedesktop xdg-desktop-portal xdg-desktop-portal-kde
}

case "${1:-install}" in
    install) install_profile ;;
    configure-environment) configure_environment "${2:-x11}" ;;
    *) echo "invalid KDE profile action: ${1:-}" >&2; exit 1 ;;
esac
