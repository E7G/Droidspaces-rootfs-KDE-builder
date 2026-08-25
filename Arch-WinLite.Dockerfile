ARG TARGETPLATFORM

FROM ogarcia/archlinux AS shim-builder
RUN printf '%s\n' \
        'Server = https://mirrors.ustc.edu.cn/archlinuxarm/$arch/$repo' \
        'Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm/$arch/$repo' \
        'Server = http://mirror.archlinuxarm.org/$arch/$repo' \
        >/etc/pacman.d/mirrorlist \
    && sed -i '/^#ParallelDownloads/c\ParallelDownloads = 2' /etc/pacman.conf \
    && { grep -qxF 'DisableDownloadTimeout' /etc/pacman.conf || sed -i '/^\[options\]/a DisableDownloadTimeout' /etc/pacman.conf; } \
    && pacman -Syu --noconfirm --needed gcc glibc
COPY scripts/ion-legacy-shim.c /tmp/ion-legacy-shim.c
COPY scripts/mi-pad4/winlite/droidspaces-tini.c /tmp/droidspaces-tini.c
RUN gcc -shared -fPIC -O2 -s \
        -o /tmp/libion-legacy-shim.so /tmp/ion-legacy-shim.c -ldl \
    && gcc -O2 -pipe -fno-plt -Wall -Wextra -Werror -s \
        -o /tmp/droidspaces-tini /tmp/droidspaces-tini.c \
    && /tmp/droidspaces-tini /usr/bin/true

FROM ogarcia/archlinux AS customizer

COPY local-packages-winlite/ /tmp/local-packages-winlite/
COPY hangover-winlite/rootfs/ /
COPY --from=shim-builder /tmp/libion-legacy-shim.so /usr/local/lib/libion-legacy-shim.so
COPY --from=shim-builder /tmp/droidspaces-tini /usr/bin/droidspaces-tini
COPY scripts/mi-pad4/mi-pad4-kwin-wayland-wrapper /usr/local/libexec/mi-pad4-kwin-wayland-wrapper
COPY scripts/mi-pad4/winlite/ /tmp/winlite/

RUN set -eux; \
    printf '%s\n' \
        'Server = https://mirrors.ustc.edu.cn/archlinuxarm/$arch/$repo' \
        'Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm/$arch/$repo' \
        'Server = http://mirror.archlinuxarm.org/$arch/$repo' \
        >/etc/pacman.d/mirrorlist; \
    sed -i '/^#ParallelDownloads/c\ParallelDownloads = 2' /etc/pacman.conf; \
    grep -qxF 'DisableDownloadTimeout' /etc/pacman.conf || \
        sed -i '/^\[options\]/a DisableDownloadTimeout' /etc/pacman.conf; \
    if [[ -f /etc/nsswitch.conf ]]; then \
        sed -i 's/^hosts:.*/hosts: files dns/' /etc/nsswitch.conf; \
    fi; \
    pacman -Sy --noconfirm --needed archlinux-keyring glibc; \
    pacman -Su --noconfirm; \
    # Runtime-only package set. Build/debug helpers that WinLite never executes
    # (gawk, iputils, unzip, PAM) are intentionally not installed explicitly.
    pacman -S --noconfirm --needed \
        bash \
        ca-certificates \
        coreutils \
        dbus \
        file \
        findutils \
        fontconfig \
        freetype2 \
        glibc \
        gnutls \
        grep \
        iproute2 \
        krb5 \
        libcap \
        libepoxy \
        libglvnd \
        libpulse \
        libunwind \
        libx11 \
        libxcomposite \
        libxcursor \
        libxext \
        libxfixes \
        libxi \
        libxinerama \
        libxkbcommon \
        libxrandr \
        libxrender \
        libxshmfence \
        libxxf86vm \
        pipewire \
        pipewire-pulse \
        procps-ng \
        sed \
        ttf-liberation \
        tzdata \
        util-linux \
        wayland \
        wireplumber \
        wqy-zenhei \
        xkeyboard-config \
        xorg-xwayland; \
    cp /etc/pacman.conf /tmp/pacman-local.conf; \
    sed -i '/^LocalFileSigLevel[[:space:]]*=/d; /^\[options\]$/a LocalFileSigLevel = Never' \
        /tmp/pacman-local.conf; \
    pacman --config /tmp/pacman-local.conf -U --noconfirm \
        /tmp/local-packages-winlite/mesa-[0-9]*.pkg.tar.*; \
    # KWin is retained only as the in-tree AnLand compositor/Android bridge.
    # The package is built without the screen-locker integration and without a
    # Plasma workspace; no Linux shell/panel/file manager is installed.
    pacman --config /tmp/pacman-local.conf -U --noconfirm \
        /tmp/local-packages-winlite/kwin-[0-9]*.pkg.tar.*; \
    if pacman -Q kscreenlocker >/dev/null 2>&1; then \
        pacman -Rdd --noconfirm kscreenlocker; \
    fi; \
    ! pacman -Q kscreenlocker >/dev/null 2>&1; \
    ! find /usr -type f \( -name 'kscreenlocker_greet' -o -name 'kcheckpass' \) -print -quit | grep -q .; \
    ! pacman -Q lxqt-panel >/dev/null 2>&1; \
    ! pacman -Q pcmanfm-qt >/dev/null 2>&1; \
    ! pacman -Q plasma-workspace >/dev/null 2>&1; \
    setcap -r /usr/bin/kwin_wayland; \
    rm -f /tmp/pacman-local.conf; \
    install -Dm755 /tmp/winlite/droidspaces-init /sbin/droidspaces-init; \
    install -Dm755 /tmp/winlite/winlite-supervisor /usr/local/bin/winlite-supervisor; \
    install -Dm755 /tmp/winlite/winlite-session /usr/local/bin/winlite-session; \
    install -Dm755 /tmp/winlite/winrun /usr/local/bin/winrun; \
    install -Dm755 /tmp/winlite/wincontainer /usr/local/bin/wincontainer; \
    install -Dm755 /usr/local/libexec/mi-pad4-kwin-wayland-wrapper \
        /usr/sbin/kwin_wayland_wrapper; \
    install -Dm644 /tmp/winlite/wine-default.reg /usr/share/winlite/wine-default.reg; \
    install -Dm644 /tmp/winlite/99-winlite-fonts.conf /etc/fonts/conf.d/99-winlite-fonts.conf; \
    install -Dm644 /tmp/winlite/90-winlite-wireplumber.conf \
        /etc/wireplumber/wireplumber.conf.d/90-winlite.conf; \
    install -Dm644 /tmp/winlite/kwinrc /usr/share/winlite/kwinrc; \
    install -Dm644 /tmp/winlite/kwinoutputconfig.json /usr/share/winlite/kwinoutputconfig.json; \
    install -Dm644 /tmp/winlite/container.config /usr/share/winlite/container.config; \
    install -Dm644 /tmp/winlite/README.txt /root/WINLITE-README.txt; \
    ln -sf /usr/local/bin/winrun /usr/local/bin/wine-run; \
    if [[ ! -e /usr/share/X11/xkb && -d /usr/share/xkeyboard-config-2 ]]; then \
        ln -s ../xkeyboard-config-2 /usr/share/X11/xkb; \
    fi; \
    if ! id user >/dev/null 2>&1; then \
        useradd -m -s /usr/bin/bash user; \
    fi; \
    ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime; \
    printf '%s\n' 'LANG=zh_CN.UTF-8' 'LC_ALL=zh_CN.UTF-8' >/etc/locale.conf; \
    sed -i 's/^#\(zh_CN.UTF-8 UTF-8\)/\1/' /etc/locale.gen; \
    locale-gen; \
    fc-cache -f; \
    fc-match -f '%{family}\n' Arial | grep -qi 'Liberation Sans'; \
    fc-match -f '%{family}\n' 'Microsoft YaHei' | grep -qi 'WenQuanYi Zen Hei'; \
    printf '%s\n' \
        '/usr/lib/aarch64-linux-gnu' \
        '/usr/lib/aarch64-linux-gnu/wine' \
        '/usr/lib/wine/aarch64-unix' \
        >/etc/ld.so.conf.d/hangover.conf; \
    ldconfig; \
    export LD_LIBRARY_PATH="/usr/lib/wine/aarch64-unix${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"; \
    install -d /usr/share/droidspaces; \
    printf '%s\n' \
        'profile=winlite' \
        'ui=winlator-style-wine-explorer-desktop' \
        'container-model=per-prefix-active-container' \
        'desktop=anland-kwin-bridge+xwayland+wine-explorer-shell' \
        'linux-desktop=none' \
        'linux-panel=none' \
        'linux-file-manager=none' \
        'dbus=session-only' \
        'pid1=droidspaces-tini' \
        'systemd=not-started' \
        'windows=hangover-11.9-winlite-ntsync+arm64ec-fex+wowbox64' \
        'sync=ntsync-auto+esync-fallback' \
        'proton-style=lean-runtime-tuning-without-steam-runtime' \
        'graphics=wine-x11-shell+xwayland+anland-opengl-kgsl' \
        'audio=pipewire-anland-minimal-policy' \
        'fonts=liberation+wqy-zenhei' \
        >/usr/share/droidspaces/winlite-profile; \
    printf '%s\n' \
        'source=E7G/mesa-for-android-container' \
        'driver=kgsl' \
        'device=adreno512' \
        >/usr/share/droidspaces/mesa-kgsl; \
    printf '%s\n' \
        'backend=anland' \
        'role=minimal-display-input-audio-bridge' \
        'sync=native-fence-worker' \
        'bufferqueue=clover-4.4-compatible' \
        >/usr/share/droidspaces/anland-kwin-package; \
    test -x /usr/bin/wine; \
    test -x /usr/bin/wineserver; \
    test -x /usr/local/bin/wincontainer; \
    grep -aFq '/dev/ntsync' /usr/bin/wineserver; \
    grep -Fq 'ntsync=compiled-in-android-uapi' /usr/share/hangover-winlite-version; \
    grep -Fq 'ntsync-fallback=esync' /usr/share/hangover-winlite-version; \
    grep -Fq 'monitor.alsa = disabled' /etc/wireplumber/wireplumber.conf.d/90-winlite.conf; \
    grep -Fq 'support.dbus = disabled' /etc/wireplumber/wireplumber.conf.d/90-winlite.conf; \
    grep -Fq '"Graphics"="x11"' /usr/share/winlite/wine-default.reg; \
    find /usr/lib -type f -name explorer.exe -print -quit | grep -q .; \
    test -e /usr/lib/wine/aarch64-windows/libarm64ecfex.dll \
        -o -e /usr/lib/aarch64-linux-gnu/wine/aarch64-windows/libarm64ecfex.dll; \
    test -e /usr/lib/wine/aarch64-windows/wowbox64.dll \
        -o -e /usr/lib/aarch64-linux-gnu/wine/aarch64-windows/wowbox64.dll; \
    : >/tmp/hangover-missing-libs; \
    for name in wine wineserver ntdll.so win32u.so winex11.drv.so winepulse.drv.so wined3d.so; do \
        find /usr/bin /usr/lib /usr/libexec -type f -name "$name" -print 2>/dev/null || true; \
    done | sort -u | while IFS= read -r elf; do \
        file -Lb "$elf" | grep -q 'ELF' || continue; \
        LD_LIBRARY_PATH="$(dirname "$elf")${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
            ldd "$elf" 2>/dev/null | grep 'not found' >>/tmp/hangover-missing-libs || true; \
    done; \
    if [[ -s /tmp/hangover-missing-libs ]]; then \
        cat /tmp/hangover-missing-libs >&2; \
        exit 1; \
    fi; \
    wine --version; \
    kwin_wayland --version; \
    # X11 is the only Winlator-style Wine display driver in this profile. The
    # native Wine Wayland driver is dead payload here, so remove it if present.
    find /usr/lib -type f \( -name 'winewayland.drv' -o -name 'winewayland.drv.so' \) -delete 2>/dev/null || true; \
    # Generated zh_CN locale + font cache are retained; source locale databases,
    # docs, headers and package caches are build-time payload only.
    rm -rf \
        /usr/include \
        /usr/lib/debug \
        /usr/share/doc \
        /usr/share/gtk-doc \
        /usr/share/info \
        /usr/share/man \
        /usr/share/i18n \
        /var/cache/pacman/pkg/* \
        /var/lib/pacman/sync/* \
        /tmp/*; \
    if [[ -d /usr/share/locale ]]; then \
        find /usr/share/locale -mindepth 1 -maxdepth 1 -type d \
            ! -name 'zh_CN' ! -name 'zh' -exec rm -rf '{}' +; \
    fi; \
    find /usr -type d -name __pycache__ -prune -exec rm -rf '{}' + 2>/dev/null || true; \
    find /usr -type f \( -name '*.a' -o -name '*.la' \) -delete

FROM scratch AS export
COPY --from=customizer / /
