ARG TARGETPLATFORM
FROM ogarcia/archlinux AS customizer

#######################################################
ARG BUILD_KDE
ARG BUILD_KDE_plus
ARG PulseAudio
ARG ENABLE_zh_tz_ARG
ARG ENABLE_binfmt_ARG
ARG ENABLE_yj_ARG
ARG ENABLE_mesa_ARG
ARG ENABLE_kfgj_ARG
ARG ENABLE_zip_ARG
ARG ENABLE_docker_ARG
ARG ENABLE_srf_ARG
ARG ENABLE_tmoe_ARG
ARG ENABLE_systemd257_ARG
ARG USERNAME
ARG ENABLE_anland_kde_ARG
ARG ENABLE_MI_PAD4_PROFILE_ARG
ARG ENABLE_MI_PAD4_FIREFOX_ARG=false
######################################################

COPY scripts/install-usb-manager.sh /usr/local/sbin/install-droidspaces-usb-manager
COPY scripts/systemd257.sh /usr/local/sbin/systemd257
COPY scripts/systemd257/ /usr/local/share/droidspaces/systemd257/
COPY scripts/ion-legacy-shim.c /tmp/ion-legacy-shim.c
COPY scripts/mi-pad4/libva-v4l2-stateful/0001-clover-firefox-prime2-copy.patch /tmp/libva-v4l2-stateful.patch
COPY scripts/mi-pad4/70-mi-pad4-cachyos.conf /tmp/70-mi-pad4-cachyos.conf
COPY scripts/mi-pad4/60-mi-pad4-ioschedulers.rules /tmp/60-mi-pad4-ioschedulers.rules
COPY scripts/mi-pad4/00-mi-pad4-journal-size.conf /tmp/00-mi-pad4-journal-size.conf
COPY scripts/mi-pad4/10-mi-pad4-system.conf /tmp/10-mi-pad4-system.conf
COPY scripts/mi-pad4/mi-pad4-cachyos-tuning.service /tmp/mi-pad4-cachyos-tuning.service
COPY scripts/mi-pad4/mi-pad4-cachyos-tuning /tmp/mi-pad4-cachyos-tuning
COPY scripts/mi-pad4/90-mi-pad4-cachyos-environment.sh /tmp/90-mi-pad4-cachyos-environment.sh
COPY scripts/mi-pad4/mi-pad4-firefox-anland-prefs.js /tmp/mi-pad4-firefox-anland-prefs.js
COPY mesa-mi-pad4/ /tmp/mesa-mi-pad4/
COPY local-packages-mi-pad4/ /tmp/local-packages-mi-pad4/

ARG MI_PAD4_V4L2_VAAPI_COMMIT=1be35ad2fc1bc66c76842d735b6ec91e11944a44
ARG MI_PAD4_SYSTEMD257_COMMIT=70b5d110be7702afc4dbce012f60d49506d513da

RUN printf '%s\n' \
    'Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm/$arch/$repo' \
    'Server = https://mirrors.ustc.edu.cn/archlinuxarm/$arch/$repo' \
    > /etc/pacman.d/mirrorlist && \
    if [ -f /etc/nsswitch.conf ]; then sed -i 's/^hosts:.*/hosts: files dns/' /etc/nsswitch.conf; fi && \
    sed -i '/^#ParallelDownloads/s/^#//' /etc/pacman.conf && \
    sed -i '/NoExtract.*locale/d' /etc/pacman.conf && \
    sed -i '/NoExtract.*i18n/d' /etc/pacman.conf && \
    pacman -Sy --noconfirm archlinux-keyring glibc && \
    pacman -Su --noconfirm && \
    cp /etc/pacman.conf /tmp/pacman-local.conf && \
    sed -i '/^LocalFileSigLevel[[:space:]]*=/d; /^\[options\]$/a LocalFileSigLevel = Never' /tmp/pacman-local.conf && \
    pacman --config /tmp/pacman-local.conf -U --noconfirm --needed /tmp/local-packages-mi-pad4/pango-*.pkg.tar.* && \
    rm -f /tmp/pacman-local.conf && \
    pacman -S --noconfirm --needed \
    # 核心工具组件 
    bash coreutils file findutils grep sed gawk curl wget ca-certificates bash-completion dbus systemd pam logrotate \
    # 用户请求的基础开发/编辑工具
    git gcc nano sudo \
    # 网络与 SSH 工具
    openssh net-tools iptables iputils iproute2 bind \
    # 用于系统监控的 procps 进程工具
    procps-ng \
    # 核心内核模块支持
    kmod tzdata && \
    ############################################## KDE支持 ################################################
    # 最小化KDE
    if [ "$BUILD_KDE" = "min" ]; then \
        pacman -S --noconfirm --needed \
        xorg-xrandr xkeyboard-config noto-fonts-cjk noto-fonts-emoji plasma-desktop pipewire pipewire-pulse wireplumber powerdevil kscreen plasma-pa ark kwin kwin-x11 upower konsole \
        dolphin pcmanfm-qt kate kinfocenter libpulse systemsettings firefox; \
    fi && \
    # 精简KDE
    if [ "$BUILD_KDE" = "conc" ]; then \
        pacman -S --noconfirm --needed \
        xorg-xrandr xkeyboard-config noto-fonts-cjk noto-fonts-emoji plasma-desktop pipewire pipewire-pulse wireplumber powerdevil kscreen plasma-pa ark kwin kwin-x11 upower konsole \
        dolphin pcmanfm-qt kate kinfocenter mesa-utils libpulse vulkan-tools aha clinfo dmidecode wayland-utils xorg-server \
        kfind plasma-systemmonitor filelight glmark2 vkmark systemsettings kscreenlocker kio-extras xdg-user-dirs dolphin-plugins ffmpegthumbs kdegraphics-thumbnailers \
        kimageformats plasma-browser-integration plasma-mobile plasma-keyboard libcanberra gstreamer gst-plugins-base gst-plugins-good sound-theme-freedesktop chromium firefox; \
    fi && \
    # Replace the generic browser with the source-built Clover variant. msm_vidc
    # decodes in hardware; PRIME_2 transfers decoded NV12 to a renderer-owned
    # dmabuf so the 16-buffer V4L2 CAPTURE queue cannot deadlock.
    if [ "$ENABLE_MI_PAD4_FIREFOX_ARG" = "true" ]; then \
        cp /etc/pacman.conf /tmp/pacman-firefox.conf && \
        sed -i '/^LocalFileSigLevel[[:space:]]*=/d; /^\[options\]$/a LocalFileSigLevel = Never' /tmp/pacman-firefox.conf && \
        pacman --config /tmp/pacman-firefox.conf -U --noconfirm \
            /tmp/local-packages-mi-pad4/firefox-153.0.3-1.3-aarch64.pkg.tar.* && \
        rm -f /tmp/pacman-firefox.conf && \
        mkdir -p /usr/share/droidspaces && \
        printf '%s\n' \
            'firefox=153.0.3-1.3' \
            'decode=msm_vidc-v4l2-hardware' \
            'transfer=prime2-gpu-copy' \
            'sync=anland-native-fence' \
            > /usr/share/droidspaces/firefox-clover-direct; \
    fi && \
    # Arch 强制安装，但是这玩意不开硬件访问会导致桌面闪退
    if [ "$BUILD_KDE" = "conc" ] || [ "$BUILD_KDE" = "min" ] ; then \
        for service in /usr/share/dbus-1/services/org.freedesktop.portal*.service; do \
            [ -e "$service" ] || continue; mv "$service" "$service.disabled"; \
        done; \
        rm -f /etc/xdg/autostart/xdg-desktop-portal*.desktop; \
    fi && \
    ######################################################################################################
    #输入法 fcitx5 (可选)
    if [ "$ENABLE_srf_ARG" = "true" ]; then \
        pacman -S --noconfirm --needed fcitx5-im; \
    fi && \
    if [ "$ENABLE_srf_ARG" = "true" ] && [ "$ENABLE_zh_tz_ARG" = "true" ]; then \
        pacman -S --noconfirm --needed fcitx5-chinese-addons; \
    fi && \
    ## 开发工具集成 (可选)
    if [ "$ENABLE_kfgj_ARG" = "true" ]; then \
        pacman -S --noconfirm --needed \
        base-devel cmake clang llvm python python-pip; \
    fi && \
    ## 压缩工具扩展 (可选)
    if [ "$ENABLE_zip_ARG" = "true" ]; then \
        pacman -S --noconfirm --needed \
        zip unzip p7zip bzip2 xz tar gzip; \
    fi && \
    ## docker (可选)
    if [ "$ENABLE_docker_ARG" = "true" ]; then \
        pacman -S --noconfirm --needed \
        docker docker-compose; \
    fi && \
    ## 集成tmoe (可选)
    if [ "$ENABLE_tmoe_ARG" = "true" ]; then \
        git clone --depth=1 https://github.com/2moe/tmoe-linux.git /usr/local/etc/tmoe-linux/git && \
        ln -sf /usr/local/etc/tmoe-linux/git/debian.sh /usr/local/bin/tmoe && \
        chmod -R 755 /usr/local/etc/tmoe-linux; \
    fi 

# 配置 Locale 与 SSH
RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    if [ "$ENABLE_zh_tz_ARG" = "true" ]; then \
        rm -f /etc/localtime && \
        install -Dm644 /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
        echo "Asia/Shanghai" > /etc/timezone && \
        echo "zh_CN.UTF-8 UTF-8" >> /etc/locale.gen && \
        locale-gen && \
        echo "LANG=zh_CN.UTF-8" > /etc/locale.conf && \
        echo "LC_ALL=zh_CN.UTF-8" >> /etc/locale.conf; \
    else \
        locale-gen && \
        echo "LANG=en_US.UTF-8" > /etc/locale.conf && \
        echo "LC_ALL=en_US.UTF-8" >> /etc/locale.conf; \
    fi && \
    # 配置 SSH 服务（禁用 root 密码登录，但允许常规密码认证）
    mkdir -p /var/run/sshd && \
    ssh-keygen -A && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    # 如果容器内存在默认的 alarm 或 arch 用户，则清理
    userdel -r alarm 2>/dev/null || true && \
    useradd -m -s /bin/bash ${USERNAME} && echo "${USERNAME}:1234" | chpasswd && \
    systemctl enable sshd

# 为所有 Arch RootFS 安装 Droidspaces USB Manager
RUN /usr/local/sbin/install-droidspaces-usb-manager --user "${USERNAME}"

# Qualcomm KGSL on the Mi Pad 4 uses the legacy Android 4.4 ION ABI.
RUN mkdir -p /usr/local/lib /usr/local/share/droidspaces && \
    gcc -shared -fPIC -O2 -o /usr/local/lib/libion-legacy-shim.so \
        /tmp/ion-legacy-shim.c -ldl && \
    printf '%s\n' 'xiaomi-mi-pad-4' 'kernel=4.4' 'gpu=kgsl' 'ion=legacy' \
        > /usr/local/share/droidspaces/kernel-profile && \
    rm -f /tmp/ion-legacy-shim.c

# 修复 Arch 登入shell没法读取 /etc/environment 环境变量的问题
RUN echo 'session  required  pam_env.so' >> /etc/pam.d/su-l

# 添加环境变量
RUN cat <<'EOF' > /etc/environment
XCURSOR_SIZE=48
DISPLAY=:5
EOF
# 音频选择
RUN if [ "$PulseAudio" = "socket" ]; then \
        echo "PULSE_SERVER=unix:/tmp/.pulse-socket" >> /etc/environment; \
    elif [ "$PulseAudio" = "tcp" ]; then \
        echo "PULSE_SERVER=tcp:127.0.0.1:4713" >> /etc/environment; \
    fi

# 输入法与 KDE 开机自启动配置
COPY scripts/start/ /tmp/droidspaces-start/
COPY scripts/mi-pad4/ /tmp/mi-pad4/
RUN <<'EOF_RUN'
    if [ "$ENABLE_srf_ARG" = "true" ]; then
    mkdir -p /home/${USERNAME}/.config/autostart
    cat <<'EOF' > /home/${USERNAME}/.config/autostart/fcitx5.desktop
[Desktop Entry]
Name=Fcitx5
GenericName=Input Method
Comment=Start Input Method
Exec=fcitx5 -d
Icon=fcitx
Terminal=false
Type=Application
Categories=System;Utility;
StartupNotify=false
NoDisplay=true
EOF
    cat <<'EOF' >> /etc/environment
XMODIFIERS=@im=fcitx5
GTK_IM_MODULE=fcitx5
QT_IM_MODULE=fcitx5
SDL_IM_MODULE=fcitx5
GLFW_IM_MODULE=fcitx
EOF
fi
    if [ "$ENABLE_mesa_ARG" = "true" ] ; then
        cat <<'EOF' >> /etc/environment
MESA_LOADER_DRIVER_OVERRIDE=kgsl
FD_KGSL_ENABLE_DMABUF=1
XWAYLAND_FORCE_KGSL_SURFACELESS=1
TU_DEBUG=noconform
LD_PRELOAD=/usr/local/lib/libion-legacy-shim.so
EOF
    fi
    echo 'export XDG_RUNTIME_DIR=/run/user/$(id -u)' >> /home/${USERNAME}/.bashrc
    if [ "$BUILD_KDE" = "min" ] || [ "$BUILD_KDE" = "conc" ] ; then
    mkdir -p /home/${USERNAME}/.config
    cat <<'EOF' > /home/${USERNAME}/.config/kwinrc
[Compositing]
Enabled=false
[Plugins]
blurEnabled=false
contrastEnabled=false
desktopgridEnabled=false
fadeEnabled=false
kwin4_effect_maximizeEnabled=false
minimizeEnabled=false
overviewEnabled=false
presentwindowsEnabled=false
scaleEnabled=false
slideEnabled=false
wobblywindowsEnabled=false
zoomEnabled=false
EOF
    cat <<'EOF' > /home/${USERNAME}/.config/kscreenlockerrc
[Daemon]
Autolock=false
LockOnResume=false
EOF
    install -m600 -o ${USERNAME} -g ${USERNAME} /tmp/mi-pad4/plasma-localerc \
        /home/${USERNAME}/.config/plasma-localerc
    install -m600 -o ${USERNAME} -g ${USERNAME} /tmp/mi-pad4/plasma-org.kde.plasma.desktop-appletsrc \
        /home/${USERNAME}/.config/plasma-org.kde.plasma.desktop-appletsrc
    install -m600 -o ${USERNAME} -g ${USERNAME} /tmp/mi-pad4/baloofilerc \
        /home/${USERNAME}/.config/baloofilerc
    install -m600 -o ${USERNAME} -g ${USERNAME} /tmp/mi-pad4/dolphinrc \
        /home/${USERNAME}/.config/dolphinrc
    install -Dm600 -o ${USERNAME} -g ${USERNAME} /tmp/mi-pad4/dolphin-global-viewproperties \
        /home/${USERNAME}/.local/share/dolphin/view_properties/global/.directory
    install -Dm600 -o ${USERNAME} -g ${USERNAME} /tmp/mi-pad4/user-places.xbel \
        /home/${USERNAME}/.local/share/user-places.xbel
    rm -f /home/${USERNAME}/.config/autostart/fcitx5.desktop
    mkdir -p /home/${USERNAME}/.config/autostart
    for service in baloo_file powerdevil polkit-kde-authentication-agent-1; do
        printf '%s\n' '[Desktop Entry]' 'Hidden=true' \
            > "/home/${USERNAME}/.config/autostart/${service}.desktop"
    done
    fi
    chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}
    if [ "$BUILD_KDE_plus" = "true" ] ; then
    install -Dm644 /tmp/droidspaces-start/plasma-x11.service /etc/systemd/system/plasma-x11.service
    mkdir -p /etc/systemd/system/multi-user.target.wants
    ln -sf /etc/systemd/system/plasma-x11.service /etc/systemd/system/multi-user.target.wants/plasma-x11.service
    fi
    rm -rf /tmp/droidspaces-start
EOF_RUN

# Mi Pad 4 runtime overlay. Droidspaces supplies the Android-side mounts and
# display socket; the patched systemd runs as PID 1 and supervises the desktop.
RUN if [ "$ENABLE_MI_PAD4_PROFILE_ARG" = "true" ]; then \
        install -Dm755 /tmp/mi-pad4/droidspaces-init /sbin/droidspaces-init && \
        install -Dm755 /tmp/mi-pad4/mi-pad4-start-wayland /usr/local/bin/mi-pad4-start-wayland && \
        install -Dm755 /tmp/mi-pad4/mi-pad4-kwin-wayland /usr/local/bin/mi-pad4-kwin-wayland && \
        install -Dm755 /tmp/mi-pad4/mi-pad4-kwin-wayland-wrapper /usr/local/libexec/mi-pad4-kwin-wayland-wrapper && \
        install -Dm755 /tmp/mi-pad4/mi-pad4-kwin-wayland-wrapper /usr/sbin/kwin_wayland_wrapper && \
        install -Dm644 /tmp/mi-pad4/mi-pad4-kwin-wrapper.hook /etc/pacman.d/hooks/mi-pad4-kwin-wrapper.hook && \
        ln -sfn ../xkeyboard-config-2 /usr/share/X11/xkb && \
        install -Dm644 /tmp/mi-pad4/mi-pad4-desktop.service /etc/systemd/system/mi-pad4-desktop.service && \
        install -Dm644 /tmp/mi-pad4/dbus-daemon.service /etc/systemd/system/dbus.service && \
        ln -sfn /dev/null /etc/systemd/system/dbus.socket && \
        ln -sfn /dev/null /etc/systemd/system/dbus-broker.service && \
         mkdir -p /etc/systemd/system/multi-user.target.wants && \
         ln -sfn ../dbus.service /etc/systemd/system/multi-user.target.wants/dbus.service && \
         ln -sfn ../mi-pad4-desktop.service /etc/systemd/system/multi-user.target.wants/mi-pad4-desktop.service && \
          ln -sfn ../mi-pad4-network.service /etc/systemd/system/multi-user.target.wants/mi-pad4-network.service && \
         ln -sfn ../mi-pad4-cachyos-tuning.service /etc/systemd/system/multi-user.target.wants/mi-pad4-cachyos-tuning.service && \
    install -Dm755 /tmp/mi-pad4/mi-pad4-file-manager /usr/local/bin/mi-pad4-file-manager && \
         ln -sfn mi-pad4-file-manager /usr/local/bin/dolphin && \
         install -Dm644 /tmp/mi-pad4/org.kde.dolphin.desktop /usr/local/share/applications/org.kde.dolphin.desktop && \
         install -Dm644 /tmp/mi-pad4-firefox-anland-prefs.js /usr/lib/firefox/defaults/pref/mi-pad4-anland.js && \
         install -Dm644 /tmp/70-mi-pad4-cachyos.conf /usr/lib/sysctl.d/70-mi-pad4-cachyos.conf && \
         install -Dm644 /tmp/60-mi-pad4-ioschedulers.rules /usr/lib/udev/rules.d/60-mi-pad4-ioschedulers.rules && \
         install -Dm644 /tmp/00-mi-pad4-journal-size.conf /usr/lib/systemd/journald.conf.d/00-mi-pad4-journal-size.conf && \
         install -Dm644 /tmp/10-mi-pad4-system.conf /usr/lib/systemd/system.conf.d/10-mi-pad4-system.conf && \
         install -Dm755 /tmp/mi-pad4-cachyos-tuning /usr/local/libexec/mi-pad4-cachyos-tuning && \
         install -Dm644 /tmp/mi-pad4-cachyos-tuning.service /etc/systemd/system/mi-pad4-cachyos-tuning.service && \
          install -Dm755 /tmp/mi-pad4/mi-pad4-network /usr/local/libexec/mi-pad4-network && \
          install -Dm644 /tmp/mi-pad4/mi-pad4-network.service /etc/systemd/system/mi-pad4-network.service && \
         install -Dm755 /tmp/90-mi-pad4-cachyos-environment.sh /etc/profile.d/90-mi-pad4-cachyos-environment.sh && \
         install -Dm644 /tmp/mi-pad4/pcmanfm-qt-settings.conf /usr/share/droidspaces/mi-pad4-profile/pcmanfm-qt-settings.conf && \
         mkdir -p /etc/pipewire/pipewire.conf.d && \
         printf '%s\n' \
             'context.properties = {' \
             '    default.clock.rate = 48000' \
             '    default.clock.quantum = 1024' \
             '    default.clock.min-quantum = 512' \
             '    default.clock.max-quantum = 2048' \
             '    default.clock.quantum-limit = 2048' \
             '}' > /etc/pipewire/pipewire.conf.d/20-mi-pad4-low-cpu.conf && \
         if [ "$ENABLE_MI_PAD4_FIREFOX_ARG" = "true" ]; then \
             install -Dm755 /tmp/mi-pad4/mi-pad4-firefox /usr/local/bin/mi-pad4-firefox && \
             for desktop in /usr/share/applications/firefox*.desktop; do \
                 [ -f "$desktop" ] || continue; \
                 sed -i 's#Exec=/usr/lib/firefox/firefox#Exec=/usr/local/bin/mi-pad4-firefox#g' "$desktop"; \
             done; \
         fi && \
        install -Dm644 /tmp/mi-pad4/dolphinrc /usr/share/droidspaces/mi-pad4-profile/dolphinrc && \
        install -Dm644 /tmp/mi-pad4/dolphin-global-viewproperties /usr/share/droidspaces/mi-pad4-profile/dolphin-global-viewproperties && \
        install -Dm644 /tmp/mi-pad4/user-places.xbel /usr/share/droidspaces/mi-pad4-profile/user-places.xbel && \
        install -Dm644 /tmp/mi-pad4/container.config /usr/share/droidspaces/mi-pad4-container.config && \
         install -Dm644 /tmp/mi-pad4/sepolicy.rule /usr/share/droidspaces/mi-pad4-sepolicy.rule && \
         mkdir -p /etc/droidspaces && \
         printf '%s\n' \
             'profile=mi-pad4-sdm660-4gb' \
             'sysctl=memory-io-thp' \
             'scheduler=schedutil-if-available' \
             "firefox-mode=$([ \"$ENABLE_MI_PAD4_FIREFOX_ARG\" = \"true\" ] && printf clover-v4l2-m2m-device || printf system-default)" \
             "firefox-clover-integration=$ENABLE_MI_PAD4_FIREFOX_ARG" \
             > /usr/share/droidspaces/cachyos-mi-pad4 && \
         printf '%s\n' 'SYSTEMD_DROIDSPACES_COMPAT=1' 'SYSTEMD_LOG_LEVEL=warning' > /etc/droidspaces/systemd-compat.env && \
        printf '%s\n' '#!/bin/bash' 'set -u' 'echo "systemd: $(/usr/lib/systemd/systemd --version 2>/dev/null | head -n 1 || true)"' 'echo "kernel: $(uname -r)"' 'echo "pid1: $(cat /proc/1/comm 2>/dev/null || true)"' 'echo "state: $(systemctl is-system-running 2>/dev/null || true)"' 'echo "desktop: $(systemctl is-active mi-pad4-desktop.service 2>/dev/null || true)"' 'echo "mode: systemd257-droidspaces"' > /usr/local/bin/droidspaces-systemd-check && \
        chmod 755 /usr/local/bin/droidspaces-systemd-check; \
    fi
# Qualcomm msm_vidc on the Mi Pad 4 uses legacy ION USERPTR queues and private
# sequence-change controls, which the upstream generic V4L2 VA driver lacks.
RUN if [ "$ENABLE_MI_PAD4_FIREFOX_ARG" = "true" ]; then \
        pacman -S --noconfirm --needed pkgconf meson ninja libva libdrm gst-plugins-bad-libs && \
        git clone https://github.com/E7G/libva-v4l2-stateful.git /tmp/libva-v4l2-stateful && \
        git -C /tmp/libva-v4l2-stateful checkout "$MI_PAD4_V4L2_VAAPI_COMMIT" && \
        git -C /tmp/libva-v4l2-stateful apply /tmp/libva-v4l2-stateful.patch && \
        meson setup /tmp/libva-v4l2-stateful/build /tmp/libva-v4l2-stateful \
            --buildtype=release --prefix=/usr && \
        meson compile -C /tmp/libva-v4l2-stateful/build && \
        meson install -C /tmp/libva-v4l2-stateful/build && \
        test -s /usr/lib/dri/v4l2_drv_video.so && \
        install -d /usr/local/lib/firefox-vaapi && \
        cc -shared -fPIC -O2 -Wl,-soname,libva-drm.so.2 \
            /tmp/mi-pad4/libva-drm-x11-shim.c \
            -o /usr/local/lib/firefox-vaapi/libva-drm.so.2 \
            -lva-x11 -lX11 -lpthread && \
        test -s /usr/local/lib/firefox-vaapi/libva-drm.so.2 && \
        mv /usr/lib/firefox/glxtest /usr/lib/firefox/glxtest.real && \
        install -Dm755 /tmp/mi-pad4/firefox-glxtest /usr/lib/firefox/glxtest && \
        rm -rf /tmp/libva-v4l2-stateful; \
    fi
# Build KWin/Xwayland natively against Arch's Qt ABI. Fedora RPMs cannot be
# reused here because their binaries require Fedora-private Qt symbols.
# pacman reinstalls KWin's stock wrapper; restore the Anland wrapper last because
# Plasma Wayland launches this fixed path and ignores KDEWM.
RUN if [ "$ENABLE_MI_PAD4_PROFILE_ARG" = "true" ]; then \
        chmod +x /tmp/mi-pad4/build-arch-anland-kwin.sh && \
        BUILD_KDE="$BUILD_KDE" /tmp/mi-pad4/build-arch-anland-kwin.sh && \
        install -Dm755 /tmp/mi-pad4/mi-pad4-kwin-wayland-wrapper /usr/local/libexec/mi-pad4-kwin-wayland-wrapper && \
        install -Dm755 /tmp/mi-pad4/mi-pad4-kwin-wayland-wrapper /usr/sbin/kwin_wayland_wrapper; \
    else \
        printf '%s\n' 'patched-kwin=not-requested' > /usr/share/droidspaces/anland-kwin-package; \
    fi
RUN rm -rf /tmp/mi-pad4

# 下载并安装 Mesa
RUN if [ "$ENABLE_mesa_ARG" = "true" ]; then \
        echo "--> [开启] 正在下载并安装最新版 Mesa 驱动..." && \
        cp /etc/pacman.conf /tmp/pacman-nosig.conf && \
        sed -i 's/.*SigLevel.*/SigLevel = Never/g' /tmp/pacman-nosig.conf && \
        if compgen -G '/tmp/mesa-mi-pad4/*.pkg.tar.*' >/dev/null; then \
            pacman --config /tmp/pacman-nosig.conf -U --noconfirm /tmp/mesa-mi-pad4/*.pkg.tar.* && \
            printf '%s\n' \
              'source=E7G/mesa-for-android-container@0f8a8d14c50612527909784e5d4dd45da628fa84' \
              'pkgbuild=E7G/archlinuxarm-PKGBUILDs@3ac8aeb07923707ac054c65b0e451b540f2ade4a' \
              'fix=proven KGSL baseline + clover 32-bit ION ABI/lifetime + KGSL dma-buf enable' \
              'egl=EGL_EXT_image_dma_buf_import' \
              > /usr/share/droidspaces/mesa-kgsl-dmabuf-import; \
        else \
            echo 'Missing CI-built Mi Pad 4 Mesa packages' >&2; exit 1; \
        fi && \
        rm -rf /tmp/mesa-mi-pad4 /tmp/pacman-nosig.conf ; \
    else \
        echo "--> [跳过] 未开启 Mesa 驱动安装"; \
    fi

# 修复容器内的 DHCP 网络服务配置
RUN mkdir -p /etc/systemd/network && \
    cat <<'EOF' > /etc/systemd/network/10-eth-dhcp.network
[Match]
Name=eth*

[Network]
DHCP=yes
IPv6AcceptRA=yes

[DHCPv4]
UseDNS=yes
UseDomains=yes
RouteMetric=100
EOF

# 应用 Android 运行环境兼容性修复（重点针对 Systemd 和 Udev）
RUN <<'EOF_RUN'
# --- 1. 常规兼容性修复 ---
# 建立 Android 网络权限组
grep -q '^aid_inet:' /etc/group     || echo 'aid_inet:x:3003:'    >> /etc/group
grep -q '^aid_net_raw:' /etc/group || echo 'aid_net_raw:x:3004:' >> /etc/group
grep -q '^aid_net_admin:' /etc/group || echo 'aid_net_admin:x:3005:' >> /etc/group

# 检查并创建 droidspaces-gpu 组
getent group droidspaces-gpu >/dev/null || groupadd -g 786 -r droidspaces-gpu
# 为 root 用户赋予访问 Android 硬件及网络的权限组
usermod -a -G aid_inet,aid_net_raw,input,video,tty,droidspaces-gpu root || true
usermod -a -G aid_inet,aid_net_raw,input,video,tty,wheel,droidspaces-gpu ${USERNAME} || true

# 确保 Arch 赋予 sudo 权限给 wheel 组
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# --- 2. 针对 Systemd 的特定修复 ---
ln -sf /dev/null /etc/systemd/system/systemd-networkd-wait-online.service
ln -sf /dev/null /etc/systemd/system/systemd-journald-audit.socket

# 优化 Journald 日志配置
cat >> /etc/systemd/journald.conf << 'EOT'
[Journal]
ReadKMsg=no
Audit=no
Storage=volatile
EOT

mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/ds-logging.conf << 'EOT'
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=200M
MaxRetentionSec=7day
MaxLevelStore=info
EOT

mkdir -p /etc/systemd/system/multi-user.target.wants
GUEST_SYSTEMD_PATH="/usr/lib/systemd/system"

if [ -f "/etc/systemd/system/dbus.service" ]; then
    ln -sf ../dbus.service "/etc/systemd/system/multi-user.target.wants/dbus.service"
elif [ -f "$GUEST_SYSTEMD_PATH/dbus.service" ]; then
    ln -sf "$GUEST_SYSTEMD_PATH/dbus.service" "/etc/systemd/system/multi-user.target.wants/dbus.service"
fi

if [ "$ENABLE_yj_ARG" = "true" ]; then
    for service in systemd-udevd.service systemd-resolved.service systemd-networkd.service NetworkManager.service; do
        if [ -f "$GUEST_SYSTEMD_PATH/$service" ]; then
            ln -sf "$GUEST_SYSTEMD_PATH/$service" "/etc/systemd/system/multi-user.target.wants/$service"
        fi
    done
else
    for service in systemd-udevd.service systemd-resolved.service systemd-networkd.service NetworkManager.service; do
        ln -sf /dev/null "/etc/systemd/system/$service"
    done
fi

# 在 systemd-logind 中禁用电源键行为处理
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/99-power-key.conf << 'EOF'
[Login]
HandlePowerKey=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandlePowerKeyLongPress=ignore
HandlePowerKeyLongPressHibernate=ignore
EOF

# 应用 udev 覆盖配置
mkdir -p /etc/systemd/system/systemd-udev-trigger.service.d
cat > /etc/systemd/system/systemd-udev-trigger.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/usr/bin/udevadm trigger --subsystem-match=usb --subsystem-match=block --subsystem-match=input --subsystem-match=tty --subsystem-match=net
EOF

# 针对只读文件系统路径覆盖
for unit in systemd-udevd.service systemd-udev-trigger.service systemd-udev-settle.service systemd-udevd-kernel.socket systemd-udevd-control.socket; do
    mkdir -p "/etc/systemd/system/${unit}.d"
    printf "[Unit]\nConditionPathIsReadWrite=\n" > "/etc/systemd/system/${unit}.d/99-readonly-fix.conf"
done

# 限制特定的网络服务
for unit in NetworkManager.service dhcpcd.service systemd-resolved.service systemd-networkd.service; do
    if [ -f "$GUEST_SYSTEMD_PATH/$unit" ] || [ -f "/etc/systemd/system/multi-user.target.wants/$unit" ]; then
        mkdir -p "/etc/systemd/system/${unit}.d"
        cat > "/etc/systemd/system/${unit}.d/99-netmode-limit.conf" << 'EOF'
[Service]
ExecCondition=
ExecCondition=/bin/sh -c "grep -qE 'net_mode=(nat|gateway)' /run/droidspaces/container.config"
EOF
    fi
done

# 仅在启用硬件访问时限制 udev 服务启动
for unit in systemd-udevd.service systemd-udev-trigger.service systemd-udev-settle.service; do
    if [ -f "$GUEST_SYSTEMD_PATH/$unit" ] || [ -f "/etc/systemd/system/multi-user.target.wants/$unit" ]; then
        mkdir -p "/etc/systemd/system/${unit}.d"
        cat > "/etc/systemd/system/${unit}.d/99-hwaccess-limit.conf" << 'EOF'
[Service]
ExecCondition=
ExecCondition=/bin/sh -c "grep -q 'enable_hw_access=1' /run/droidspaces/container.config"
EOF
    fi
done

# 针对 Android 环境微调日志轮转
if [ -f /etc/logrotate.conf ]; then
    sed -i 's/^#maxsize.*/maxsize 50M/' /etc/logrotate.conf
    if ! grep -q "maxsize 50M" /etc/logrotate.conf; then
        echo "maxsize 50M" >> /etc/logrotate.conf
    fi
fi

echo "Post-extraction fixes applied on $(date)" > /etc/droidspaces/build-info
EOF_RUN

# 注入 binfmt 服务脚本
COPY scripts/binfmt/qemu-binfmt-register.sh /usr/local/bin/
COPY scripts/binfmt/qemu-binfmt-register.service /etc/systemd/system/

RUN if [ "$ENABLE_binfmt_ARG" = "false" ]; then \
        rm -rf /usr/local/bin/qemu-binfmt-register.sh && \
        rm -rf /etc/systemd/system/qemu-binfmt-register.service ; \
    fi

RUN if [ "$ENABLE_binfmt_ARG" = "true" ]; then \
        chmod +x /usr/local/bin/qemu-binfmt-register.sh && \
        chmod 644 /etc/systemd/system/qemu-binfmt-register.service && \
        mkdir -p /etc/systemd/system/multi-user.target.wants && \
        ln -sf /etc/systemd/system/qemu-binfmt-register.service /etc/systemd/system/multi-user.target.wants/qemu-binfmt-register.service && \
        pacman -S --noconfirm --needed qemu-user qemu-user-binfmt && \
        rm -rf /var/cache/pacman/pkg/* /var/lib/pacman/sync/* ; \
    else \
        rm -f /usr/local/bin/qemu-binfmt-register.sh /etc/systemd/system/qemu-binfmt-register.service; \
    fi

# 可选：为 systemd 258+ 发行版构建 systemd 257 旧内核兼容运行时。
RUN if [ "$ENABLE_systemd257_ARG" = "true" ]; then \
        SYSTEMD257_FORCE_REBUILD="$ENABLE_MI_PAD4_PROFILE_ARG" \
        SYSTEMD257_REF="$MI_PAD4_SYSTEMD257_COMMIT" \
        SYSTEMD257_PATCH_DIR=/usr/local/share/droidspaces/systemd257 \
        bash /usr/local/sbin/systemd257; \
    else \
        echo "--> [跳过] 未启用 systemd 257 旧内核兼容"; \
    fi && \
    rm -f /usr/local/sbin/systemd257 && \
    rm -rf /usr/local/share/droidspaces/systemd257

# USB Manager performs a full pacman -Syu on Arch guests. Reinstall the
# source-built Clover package after every package transaction so a repository
# Firefox update cannot silently replace the hardware-decoding build.
RUN if [ "$ENABLE_MI_PAD4_FIREFOX_ARG" = "true" ]; then \
        cp /etc/pacman.conf /tmp/pacman-firefox-final.conf && \
        sed -i '/^LocalFileSigLevel[[:space:]]*=/d; /^\[options\]$/a LocalFileSigLevel = Never' /tmp/pacman-firefox-final.conf && \
        pacman --config /tmp/pacman-firefox-final.conf -U --noconfirm \
            /tmp/local-packages-mi-pad4/firefox-153.0.3-1.3-aarch64.pkg.tar.* && \
        rm -f /tmp/pacman-firefox-final.conf; \
    fi

# Mi Pad 4 runtime keeps the normal daily KDE applications. Only build-time
# compilers and source-control tools are removed; file management, archives,
# editor, settings and common network utilities remain available.
RUN if [ "$ENABLE_MI_PAD4_PROFILE_ARG" = "true" ]; then \
        if [ "$ENABLE_kfgj_ARG" != "true" ]; then \
            for package in gcc git; do \
                if pacman -Qq "$package" >/dev/null 2>&1; then \
                    pacman -Rns --noconfirm "$package" || true; \
                fi; \
            done; \
        fi; \
        for unit in \
            systemd-rfkill.service systemd-rfkill.socket \
            systemd-timesyncd.service systemd-timesyncd.socket \
            man-db.timer updatedb.timer fstrim.timer; do \
            ln -sfn /dev/null "/etc/systemd/system/$unit"; \
        done; \
        mkdir -p /etc/systemd/coredump.conf.d; \
        printf '%s\n' '[Coredump]' 'Storage=none' 'ProcessSizeMax=0' \
            > /etc/systemd/coredump.conf.d/99-mi-pad4.conf; \
    fi && \
    rm -rf /var/cache/pacman/pkg/* /var/lib/pacman/sync/* /tmp/local-packages-mi-pad4 && \
    rm -f /tmp/70-mi-pad4-cachyos.conf /tmp/60-mi-pad4-ioschedulers.rules \
          /tmp/00-mi-pad4-journal-size.conf /tmp/10-mi-pad4-system.conf \
          /tmp/mi-pad4-cachyos-tuning /tmp/mi-pad4-cachyos-tuning.service \
          /tmp/mi-pad4-firefox-anland-prefs.js
# 阶段 2：将完整的根文件系统导出到 scratch（空白层），以便外部直接提取或打包成 tarfs
FROM scratch AS export
COPY --from=customizer / /
