#!/bin/bash

set -euo pipefail

# Ubuntu 26.04 currently ships several Plasma applet metadata files without the
# matching QML payloads.  Fetch the matching upstream Plasma sources in CI and
# install only the applets needed by the Mi Pad 4 profile.  Nothing is stored in
# this repository or downloaded on the developer machine.

readonly DESKTOP_URL="https://download.kde.org/stable/plasma/6.6.5/plasma-desktop-6.6.5.tar.xz"
readonly DESKTOP_SHA256="1d758dffcc42e1d3fbbfea0500009d3dc795cf1313b93b574da83624177085f3"
readonly WORKSPACE_URL="https://download.kde.org/stable/plasma/6.6.5/plasma-workspace-6.6.5.tar.xz"
readonly WORKSPACE_SHA256="64d753cadcb9cde6ac09eeedf6b02ec5ccdfbd01722c5e9f2533fd0993b0d854"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

fetch_archive() {
    local url="$1" sha256="$2" name="$3" archive="$tmpdir/$3"
    curl -fsSL --retry 5 --retry-delay 2 "$url" -o "$archive"
    printf '%s  %s\n' "$sha256" "$archive" | sha256sum -c -
    tar -xJf "$archive" -C "$tmpdir"
}

fetch_archive "$DESKTOP_URL" "$DESKTOP_SHA256" plasma-desktop.tar.xz
fetch_archive "$WORKSPACE_URL" "$WORKSPACE_SHA256" plasma-workspace.tar.xz

install_payload() {
    local source="$1" destination="$2"
    rm -rf "$destination"
    install -d "$(dirname "$destination")"
    cp -a "$source" "$destination"
}

desktop_root="$tmpdir/plasma-desktop-6.6.5"
workspace_root="$tmpdir/plasma-workspace-6.6.5"

install_payload "$desktop_root/applets/kickoff" \
    /usr/share/plasma/plasmoids/org.kde.plasma.kickoff
install_payload "$desktop_root/applets/taskmanager" \
    /usr/share/plasma/plasmoids/org.kde.plasma.taskmanager
install_payload "$desktop_root/containments/panel" \
    /usr/share/plasma/containments/org.kde.panel

install_payload "$workspace_root/applets/clipboard" \
    /usr/share/plasma/plasmoids/org.kde.plasma.clipboard
install_payload "$workspace_root/applets/devicenotifier" \
    /usr/share/plasma/plasmoids/org.kde.plasma.devicenotifier
install_payload "$workspace_root/applets/digital-clock" \
    /usr/share/plasma/plasmoids/org.kde.plasma.digitalclock
install_payload "$workspace_root/applets/notifications" \
    /usr/share/plasma/plasmoids/org.kde.plasma.notifications
install_payload "$workspace_root/applets/panelspacer" \
    /usr/share/plasma/plasmoids/org.kde.plasma.panelspacer
install_payload "$workspace_root/applets/systemtray" \
    /usr/share/plasma/plasmoids/org.kde.plasma.systemtray

test -f /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/main.qml
test -f /usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/qml/main.qml
test -f /usr/share/plasma/plasmoids/org.kde.plasma.digitalclock/contents/ui/main.qml
