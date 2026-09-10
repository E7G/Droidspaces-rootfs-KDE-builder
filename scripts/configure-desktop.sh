#!/usr/bin/env bash
set -euo pipefail

desktop="${1:-none}"
backend="${2:-x11}"
autostart="${3:-false}"
username="${4:-droidspaces}"
profile_dir="${DROIDSPACES_DESKTOP_PROFILE_DIR:-/usr/local/lib/droidspaces/desktops}"

case "$desktop" in none|kde|kde-mobile) ;; *) echo "invalid desktop: $desktop" >&2; exit 1 ;; esac
case "$backend" in x11|anland-wayland) ;; *) echo "invalid display backend: $backend" >&2; exit 1 ;; esac
case "$autostart" in true|false) ;; *) echo "invalid desktop autostart: $autostart" >&2; exit 1 ;; esac
[[ -n "$username" ]] || { echo "username is required" >&2; exit 1; }

if [[ "$desktop" == none && "$backend" != x11 ]]; then
    echo "desktop=none only supports x11/no-display mode" >&2
    exit 1
fi
if [[ "$desktop" == kde-mobile && "$backend" != anland-wayland ]]; then
    echo "kde-mobile requires anland-wayland" >&2
    exit 1
fi

cat > /etc/droidspaces-desktop.conf <<EOF
DESKTOP=$desktop
DISPLAY_BACKEND=$backend
DESKTOP_USER=$username
EOF
chmod 0644 /etc/droidspaces-desktop.conf

if [[ "$desktop" != none ]]; then
    "$profile_dir/$desktop.sh" configure-environment "$backend"
fi

install -d -m 0755 "/home/$username/.config"
if [[ "$desktop" == kde || "$desktop" == kde-mobile ]]; then
    cat > "/home/$username/.config/kwinrc" <<'EOF'
[Compositing]
Enabled=false
[Plugins]
blurEnabled=false
contrastEnabled=false
wobblywindowsEnabled=false
EOF
    cat > "/home/$username/.config/kscreenlockerrc" <<'EOF'
[Daemon]
Autolock=false
LockOnResume=false
EOF
fi
chown -R "$username:$username" "/home/$username"

rm -f /etc/systemd/system/multi-user.target.wants/desktop-session.service
if [[ "$autostart" == true && "$desktop" != none ]]; then
    cat > /etc/systemd/system/desktop-session.service <<EOF
[Unit]
Description=Droidspaces desktop session
After=local-fs.target dbus.service
Wants=dbus.service
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
User=$username
PAMName=login
EnvironmentFile=-/etc/environment
ExecStart=/usr/local/bin/start-desktop-session
Restart=on-failure
RestartSec=3s
KillMode=control-group
LimitNOFILE=8192
KeyringMode=inherit

[Install]
WantedBy=multi-user.target
EOF
    install -d -m 0755 /etc/systemd/system/multi-user.target.wants
    ln -sfn ../desktop-session.service /etc/systemd/system/multi-user.target.wants/desktop-session.service
fi
