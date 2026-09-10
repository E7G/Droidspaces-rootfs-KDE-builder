FROM ogarcia/archlinux AS customizer

ARG DESKTOP=kde
ARG DESKTOP_AUTOSTART=false
ARG DISPLAY_BACKEND=anland-wayland
ARG DEVICE_PROFILE=generic
ARG USERNAME=droidspaces
ARG PulseAudio=none
ARG ENABLE_zh_tz_ARG=true
ARG ENABLE_mesa_ARG=true
ARG ENABLE_srf_ARG=true
ARG ENABLE_kfgj_ARG=false
ARG ENABLE_zip_ARG=true
ARG ENABLE_docker_ARG=false
ARG ENABLE_tmoe_ARG=false
ARG ENABLE_systemd257_ARG=false
ARG ENABLE_MI_PAD4_FIREFOX_ARG=false
ARG BUILD_CLOVER_KWIN=true

# Pin the generic component-management layer to the Gold revision used as the
# clean architecture baseline. Device-specific code remains in this repository.
ARG GOLD_FRAMEWORK_REV=1df25ef6a52c10b9915126286d968bbccc233cd4

COPY scripts/install-usb-manager.sh /usr/local/sbin/install-droidspaces-usb-manager
COPY scripts/systemd257.sh /usr/local/sbin/systemd257
COPY scripts/systemd257/ /usr/local/share/droidspaces/systemd257/
COPY scripts/install-desktop.sh /usr/local/sbin/install-desktop
COPY scripts/configure-desktop.sh /usr/local/sbin/configure-desktop
COPY scripts/start-desktop-session.sh /usr/local/bin/start-desktop-session
COPY scripts/desktops/ /usr/local/lib/droidspaces/desktops/
COPY scripts/install-device-profile.sh /usr/local/sbin/install-device-profile
COPY scripts/device-profiles/ /usr/local/lib/droidspaces/device-profiles/
COPY scripts/app-compat/droidspaces-launch-app /usr/local/bin/droidspaces-launch-app
COPY scripts/ion-legacy-shim.c /opt/droidspaces/device-assets/ion-legacy-shim.c
COPY scripts/mi-pad4/ /opt/droidspaces/device-assets/mi-pad4/
COPY local-packages-mi-pad4/ /opt/droidspaces/local-packages-mi-pad4/

RUN chmod 0755 \
        /usr/local/sbin/install-droidspaces-usb-manager \
        /usr/local/sbin/systemd257 \
        /usr/local/sbin/install-desktop \
        /usr/local/sbin/configure-desktop \
        /usr/local/sbin/install-device-profile \
        /usr/local/bin/start-desktop-session \
        /usr/local/bin/droidspaces-launch-app \
        /usr/local/lib/droidspaces/desktops/*.sh \
        /usr/local/lib/droidspaces/device-profiles/*.sh && \
    sed -i '/^#ParallelDownloads/s/^#//' /etc/pacman.conf && \
    sed -i '/NoExtract.*locale/d; /NoExtract.*i18n/d' /etc/pacman.conf && \
    pacman -Sy --noconfirm archlinux-keyring glibc && \
    pacman -Su --noconfirm && \
    pacman -S --noconfirm --needed \
        bash jq dialog coreutils file findutils grep sed gawk curl wget ca-certificates \
        bash-completion dbus systemd pam git gcc nano sudo openssh net-tools iptables \
        iputils iproute2 bind procps-ng kmod tzdata tar xz zstd logrotate fastfetch && \
    /usr/local/sbin/install-desktop "$DESKTOP"

# Keep Gold's current component management/updater as the generic layer rather
# than cloning its whole RootFS. The revision is pinned for reproducible builds.
RUN set -eux; \
    base="https://raw.githubusercontent.com/Goldzxcbug/Droidspaces-rootfs-Desktop-builder/${GOLD_FRAMEWORK_REV}/scripts/tui"; \
    curl -fL "$base/install-anland-kde.sh" -o /usr/local/sbin/install-anland-kde; \
    curl -fL "$base/install-anland-gnome.sh" -o /usr/local/sbin/install-anland-gnome; \
    curl -fL "$base/install-mesa.sh" -o /usr/local/sbin/install-mesa; \
    curl -fL "$base/install-hangover-wine.sh" -o /usr/local/sbin/install-hangover-wine; \
    curl -fL "$base/install-winefonts.sh" -o /usr/local/sbin/install-winefonts; \
    curl -fL "$base/droidspaces-tui.sh" -o /usr/local/bin/droidspaces-tui; \
    chmod 0755 /usr/local/sbin/install-anland-* /usr/local/sbin/install-mesa \
        /usr/local/sbin/install-hangover-wine /usr/local/sbin/install-winefonts \
        /usr/local/bin/droidspaces-tui; \
    ln -sfn droidspaces-tui /usr/local/bin/dstui; \
    ln -sfn droidspaces-tui /usr/local/bin/ds-tui

# Generic Anland gets Gold's rolling patched KWin/XWayland packages. Clover is
# intentionally excluded: its device profile builds the E7G Android-4.4/KGSL
# backend against the current Arch Qt ABI instead.
RUN if [ "$DISPLAY_BACKEND" = "anland-wayland" ] && [ "$DESKTOP" != "none" ] && \
       [ "$DEVICE_PROFILE" != "mi-pad4-clover" ]; then \
        /usr/local/sbin/install-anland-kde --1; \
    fi

# Locale, account and login session setup.
RUN echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen && \
    if [ "$ENABLE_zh_tz_ARG" = "true" ]; then \
        echo 'zh_CN.UTF-8 UTF-8' >> /etc/locale.gen && \
        ln -sfn /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
        echo 'LANG=zh_CN.UTF-8' > /etc/locale.conf; \
    else \
        echo 'LANG=en_US.UTF-8' > /etc/locale.conf; \
    fi && \
    locale-gen && \
    rm -f /etc/locale.conf.tmp && \
    (userdel -r alarm 2>/dev/null || true) && \
    if ! id "$USERNAME" >/dev/null 2>&1; then useradd -m -s /bin/bash "$USERNAME"; fi && \
    echo "$USERNAME:1234" | chpasswd && \
    usermod -aG wheel "$USERNAME" && \
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers && \
    mkdir -p /var/run/sshd && ssh-keygen -A && \
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    systemctl enable sshd

# su/su -l must establish a usable PAM/systemd session when the kernel allows it.
RUN for pam_file in /etc/pam.d/su /etc/pam.d/su-l; do \
        grep -qE '^[[:space:]-]*session[[:space:]].*pam_systemd\.so' "$pam_file" || \
            sed -i '/^[[:space:]]*session[[:space:]].*pam_unix\.so/a session optional pam_systemd.so' "$pam_file"; \
    done && \
    grep -qE '^[[:space:]-]*session[[:space:]].*pam_env\.so' /etc/pam.d/su-l || \
        echo 'session required pam_env.so' >> /etc/pam.d/su-l

# Generic environment only. GPU/ION and toolkit backend overrides are NOT global.
RUN : > /etc/environment && \
    if [ "$PulseAudio" = "socket" ]; then \
        echo 'PULSE_SERVER=unix:/tmp/.pulse-socket' >> /etc/environment; \
    elif [ "$PulseAudio" = "tcp" ]; then \
        echo 'PULSE_SERVER=tcp:127.0.0.1:4713' >> /etc/environment; \
    fi

# Optional input method. It is safe to keep toolkit IM modules global; display
# backend selection remains automatic so old Qt/X11 applications still work.
RUN if [ "$ENABLE_srf_ARG" = "true" ]; then \
        pacman -S --noconfirm --needed fcitx5-im && \
        if [ "$ENABLE_zh_tz_ARG" = "true" ]; then pacman -S --noconfirm --needed fcitx5-chinese-addons; fi && \
        printf '%s\n' \
            'XMODIFIERS=@im=fcitx5' \
            'GTK_IM_MODULE=fcitx5' \
            'QT_IM_MODULE=fcitx5' \
            'SDL_IM_MODULE=fcitx5' >> /etc/environment; \
    fi

# Generic Mesa comes from Gold's current component installer. Clover must use
# the known-good E7G package set and is handled in its device profile below.
RUN if [ "$ENABLE_mesa_ARG" = "true" ] && [ "$DEVICE_PROFILE" != "mi-pad4-clover" ]; then \
        /usr/local/sbin/install-mesa --1; \
    fi

# Optional utility layers retained from the old builder.
RUN if [ "$ENABLE_kfgj_ARG" = "true" ]; then \
        pacman -S --noconfirm --needed base-devel cmake clang llvm python python-pip; \
    fi && \
    if [ "$ENABLE_zip_ARG" = "true" ]; then \
        pacman -S --noconfirm --needed zip unzip p7zip bzip2 gzip; \
    fi && \
    if [ "$ENABLE_docker_ARG" = "true" ]; then \
        pacman -S --noconfirm --needed docker docker-compose; \
    fi && \
    if [ "$ENABLE_tmoe_ARG" = "true" ]; then \
        git clone --depth=1 https://github.com/2moe/tmoe-linux.git /usr/local/etc/tmoe-linux/git && \
        ln -sfn /usr/local/etc/tmoe-linux/git/debian.sh /usr/local/bin/tmoe; \
    fi

# Android/Droidspaces baseline groups and conservative systemd settings.
RUN getent group aid_inet >/dev/null || groupadd -g 3003 aid_inet && \
    getent group aid_net_raw >/dev/null || groupadd -g 3004 aid_net_raw && \
    getent group aid_net_admin >/dev/null || groupadd -g 3005 aid_net_admin && \
    getent group droidspaces-gpu >/dev/null || groupadd -g 786 -r droidspaces-gpu && \
    usermod -aG aid_inet,aid_net_raw,input,video,tty,droidspaces-gpu root && \
    usermod -aG aid_inet,aid_net_raw,input,video,tty,droidspaces-gpu,wheel "$USERNAME" && \
    mkdir -p /etc/systemd/journald.conf.d && \
    printf '%s\n' '[Journal]' 'Storage=volatile' 'RuntimeMaxUse=200M' 'MaxRetentionSec=7day' \
        > /etc/systemd/journald.conf.d/20-droidspaces.conf && \
    mkdir -p /etc/systemd/logind.conf.d && \
    printf '%s\n' '[Login]' 'HandlePowerKey=ignore' 'HandleSuspendKey=ignore' 'HandleHibernateKey=ignore' \
        > /etc/systemd/logind.conf.d/20-droidspaces.conf

# Install the selected device profile after the generic userland is complete.
RUN DROIDSPACES_ENABLE_MESA="$ENABLE_mesa_ARG" \
    DROIDSPACES_BUILD_CLOVER_KWIN="$BUILD_CLOVER_KWIN" \
    DROIDSPACES_MI_PAD4_FIREFOX="$ENABLE_MI_PAD4_FIREFOX_ARG" \
        /usr/local/sbin/install-device-profile "$DEVICE_PROFILE"

# Desktop configuration is intentionally separate from the device profile.
RUN /usr/local/sbin/configure-desktop \
        "$DESKTOP" "$DISPLAY_BACKEND" "$DESKTOP_AUTOSTART" "$USERNAME" && \
    /usr/local/sbin/install-droidspaces-usb-manager --user "$USERNAME"

# Optional systemd-257 compatibility remains a generic component, not a Clover
# hard dependency. Use only when the target legacy kernel actually needs it.
RUN if [ "$ENABLE_systemd257_ARG" = "true" ]; then /usr/local/sbin/systemd257; fi

RUN pacman -Scc --noconfirm || true && \
    rm -rf /var/cache/pacman/pkg/* /tmp/* /var/tmp/*

FROM scratch
COPY --from=customizer / /
