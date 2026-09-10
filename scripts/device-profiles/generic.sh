#!/usr/bin/env bash
set -euo pipefail

[[ "${1:-install}" == install ]] || { echo "invalid device profile action" >&2; exit 1; }

install -d -m 0755 /etc /usr/share/droidspaces
cat > /etc/droidspaces-device.conf <<'EOF'
DEVICE_PROFILE=generic
DROIDSPACES_GPU=auto
DROIDSPACES_ION=auto
EOF
cat > /usr/share/droidspaces/device-profile <<'EOF'
profile=generic
hardware-policy=distribution-default
app-env=device-neutral
EOF
