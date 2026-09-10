#!/usr/bin/env bash
set -euo pipefail

[[ "${1:-install}" == install ]] || { echo "invalid device profile action" >&2; exit 1; }

assets="${DROIDSPACES_MI_PAD4_ASSETS:-/opt/droidspaces/device-assets/mi-pad4}"
local_pkgs="${DROIDSPACES_MI_PAD4_PACKAGES:-/opt/droidspaces/local-packages-mi-pad4}"
[[ -d "$assets" ]] || { echo "Mi Pad 4 assets not found: $assets" >&2; exit 1; }

case "$(uname -m)" in aarch64|arm64) ;; *) echo "mi-pad4-clover requires aarch64" >&2; exit 1 ;; esac

install -d -m 0755 /etc /usr/share/droidspaces /usr/local/lib /usr/local/bin /usr/local/libexec
cat > /etc/droidspaces-device.conf <<'EOF'
DEVICE_PROFILE=mi-pad4-clover
DROIDSPACES_GPU=kgsl
DROIDSPACES_ION=legacy
DROIDSPACES_KERNEL_COMPAT=4.4
EOF

# Clover uses the legacy Android ION ABI. Build the shim, but NEVER put it in
# /etc/environment. Only the compositor wrapper below receives LD_PRELOAD.
pacman -S --noconfirm --needed gcc libdrm
cc -shared -fPIC -O2 -o /usr/local/lib/libion-legacy-shim.so \
    "$assets/../ion-legacy-shim.c" -ldl

# Install already-built ABI compatibility packages when the workflow supplied
# them. KIO/Pango are device-profile details rather than generic Arch policy.
if [[ -d "$local_pkgs" ]]; then
    cp /etc/pacman.conf /tmp/pacman-mi-pad4.conf
    sed -i '/^LocalFileSigLevel[[:space:]]*=/d; /^\[options\]$/a LocalFileSigLevel = Never' /tmp/pacman-mi-pad4.conf
    shopt -s nullglob
    pango_pkgs=("$local_pkgs"/pango-*.pkg.tar.*)
    kio_pkgs=("$local_pkgs"/kio-*.pkg.tar.*)
    ((${#pango_pkgs[@]} == 0)) || pacman --config /tmp/pacman-mi-pad4.conf -U --noconfirm "${pango_pkgs[@]}"
    if ((${#kio_pkgs[@]} > 0)); then
        pacman --config /tmp/pacman-mi-pad4.conf -U --noconfirm "${kio_pkgs[@]}"
        install -d -m 0755 /usr/share/droidspaces
        echo 'patched-kio=named-worker-socket-for-kernel-4.4' > /usr/share/droidspaces/kio-runtime-named-socket
    fi

    if [[ "${DROIDSPACES_ENABLE_MESA:-true}" == true ]]; then
        mesa_pkgs=("$local_pkgs"/mesa-[0-9]*.pkg.tar.*)
        freedreno_pkgs=("$local_pkgs"/vulkan-freedreno-*.pkg.tar.*)
        implicit_pkgs=("$local_pkgs"/vulkan-mesa-implicit-layers-*.pkg.tar.*)
        if ((${#mesa_pkgs[@]} == 0 || ${#freedreno_pkgs[@]} == 0)); then
            echo "Mi Pad 4 Mesa artifacts are missing; refusing to install generic Mesa on Clover" >&2
            exit 1
        fi
        pacman --config /tmp/pacman-mi-pad4.conf -U --noconfirm \
            "${mesa_pkgs[@]}" "${freedreno_pkgs[@]}" "${implicit_pkgs[@]}"
        cat > /usr/share/droidspaces/mesa-device-profile <<'EOF'
profile=mi-pad4-clover
renderer=kgsl
ion=legacy-32bit-compat
dmabuf=enabled
EOF
    fi
    rm -f /tmp/pacman-mi-pad4.conf
fi

# Device runtime/tuning. Do not install or enable the old mi-pad4-desktop.service:
# its broad pkill rules can kill independent Linux Apps sessions.
install -Dm755 "$assets/droidspaces-init" /sbin/droidspaces-init
install -Dm755 "$assets/mi-pad4-start-wayland" /usr/local/bin/mi-pad4-start-wayland
install -Dm755 "$assets/mi-pad4-kwin-wayland" /usr/local/bin/mi-pad4-kwin-wayland
install -Dm755 "$assets/mi-pad4-network" /usr/local/libexec/mi-pad4-network
install -Dm644 "$assets/mi-pad4-network.service" /etc/systemd/system/mi-pad4-network.service
install -Dm755 "$assets/mi-pad4-cachyos-tuning" /usr/local/libexec/mi-pad4-cachyos-tuning
install -Dm644 "$assets/mi-pad4-cachyos-tuning.service" /etc/systemd/system/mi-pad4-cachyos-tuning.service
install -Dm644 "$assets/70-mi-pad4-cachyos.conf" /usr/lib/sysctl.d/70-mi-pad4-cachyos.conf
install -Dm644 "$assets/60-mi-pad4-ioschedulers.rules" /usr/lib/udev/rules.d/60-mi-pad4-ioschedulers.rules
install -Dm644 "$assets/00-mi-pad4-journal-size.conf" /usr/lib/systemd/journald.conf.d/00-mi-pad4-journal-size.conf
install -Dm644 "$assets/10-mi-pad4-system.conf" /usr/lib/systemd/system.conf.d/10-mi-pad4-system.conf
install -Dm755 "$assets/90-mi-pad4-cachyos-environment.sh" /etc/profile.d/90-mi-pad4-cachyos-environment.sh
install -Dm644 "$assets/container.config" /usr/share/droidspaces/mi-pad4-container.config
install -Dm644 "$assets/sepolicy.rule" /usr/share/droidspaces/mi-pad4-sepolicy.rule

install -d -m 0755 /etc/systemd/system/multi-user.target.wants
ln -sfn ../mi-pad4-network.service /etc/systemd/system/multi-user.target.wants/mi-pad4-network.service
ln -sfn ../mi-pad4-cachyos-tuning.service /etc/systemd/system/multi-user.target.wants/mi-pad4-cachyos-tuning.service

# Build the Clover-specific Anland backend/KWin/XWayland against the current Arch
# Qt ABI. This is the device-specialized part retained from E7G's old image.
if [[ "${DROIDSPACES_BUILD_CLOVER_KWIN:-true}" == true ]]; then
    getent passwd user >/dev/null || useradd -m -s /bin/bash user
    build_kio=true
    [[ -f /usr/share/droidspaces/kio-runtime-named-socket ]] && build_kio=false
    sed -i 's/droidspaces-mode=wslg-v2-compatible/droidspaces-mode=anland-single-session/' "$assets/build-arch-anland-kwin.sh"
    BUILD_KDE=min \
    BUILD_KIO="$build_kio" \
    BUILD_PLASMA_WORKSPACE=false \
    ANLAND_ARCH_SOURCE=local \
        bash "$assets/build-arch-anland-kwin.sh"
fi

# Compositor-only hardware environment. Linux applications launched by
# droidspaces-launch-app explicitly drop LD_PRELOAD, so the ioctl shim cannot
# break unrelated Qt/GTK/Electron software.
cat > /usr/local/bin/droidspaces-anland-kwin <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
unset LIBGL_ALWAYS_SOFTWARE QT_QUICK_BACKEND QT_OPENGL
export MESA_LOADER_DRIVER_OVERRIDE=kgsl
export FD_FORCE_KGSL=1
export FD_KGSL_ENABLE_DMABUF=1
export XWAYLAND_FORCE_KGSL_SURFACELESS=1
export KWIN_DISABLE_VULKAN=1
export ANLAND_NATIVE_FENCE=1
if [[ -f /usr/local/lib/libion-legacy-shim.so ]]; then
    export LD_PRELOAD=/usr/local/lib/libion-legacy-shim.so
fi
exec /usr/bin/kwin_wayland "$@"
EOF
chmod 0755 /usr/local/bin/droidspaces-anland-kwin

# Optional Clover Firefox stays profile-scoped. Never replace the generic
# browser unless an explicitly staged, known-good package exists.
if [[ "${DROIDSPACES_MI_PAD4_FIREFOX:-false}" == true ]]; then
    shopt -s nullglob
    firefox_pkgs=("$local_pkgs"/firefox-*.pkg.tar.*)
    ((${#firefox_pkgs[@]} > 0)) || { echo "Clover Firefox artifact missing" >&2; exit 1; }
    cp /etc/pacman.conf /tmp/pacman-firefox.conf
    sed -i '/^LocalFileSigLevel[[:space:]]*=/d; /^\[options\]$/a LocalFileSigLevel = Never' /tmp/pacman-firefox.conf
    pacman --config /tmp/pacman-firefox.conf -U --noconfirm "${firefox_pkgs[@]}"
    rm -f /tmp/pacman-firefox.conf
    [[ ! -f "$assets/mi-pad4-firefox" ]] || install -Dm755 "$assets/mi-pad4-firefox" /usr/local/bin/mi-pad4-firefox
    [[ ! -f "$assets/mi-pad4-firefox-anland-prefs.js" ]] || install -Dm644 "$assets/mi-pad4-firefox-anland-prefs.js" /usr/lib/firefox/defaults/pref/mi-pad4-anland.js
fi

cat > /usr/share/droidspaces/device-profile <<'EOF'
profile=mi-pad4-clover
soc=sdm660
gpu=adreno-512-kgsl
kernel=4.4-compatible
ion=legacy
compositor-env=profile-scoped
wslg=disabled-waiting-for-anland-v6
EOF
