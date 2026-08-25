# WinLite Winlator-style container mode

WinLite is intentionally not a second Linux desktop. Its visible shell is Wine Explorer, while Linux only provides the minimum Droidspaces/AnLand bridge required to put that Windows desktop on Android.

## Runtime stack

`droidspaces-tini -> dbus-run-session -> PipeWire -> WirePlumber(policy) -> KWin AnLand bridge -> Xwayland -> Wine Explorer`

KWin is compiled as a bridge-only package for this profile. Plasma Workspace, KIO, KCMs, notifications, global-shortcut daemon, Activities, EIS, decorations, KScreenLocker and Plasma/QML desktop runtime dependencies are excluded from the WinLite KWin package.

Wine Explorer owns the desktop, taskbar, Start menu, tray and file browsing. The Wine graphics driver is X11 only, matching Winlator's virtual-desktop model behind its X server; WinLite uses Xwayland because the current Droidspaces AnLand backend is implemented inside KWin.

## Containers

Each WinLite container owns an independent prefix under:

`~/.winlite/containers/<name>/.wine`

The active container name is stored in:

`~/.winlite/active-container`

`~/Windows` is shared between containers and is exposed as `G:` plus a `Windows` folder on each Wine desktop. The former `~/.wine-winlite` path is migrated once and then kept as a compatibility symlink to the active prefix.

Use `wincontainer create`, `wincontainer list`, `wincontainer use`, `wincontainer current`, `wincontainer path` and `wincontainer prefix` to manage prefixes. `winrun --container <name> ...` launches against a selected container without changing the active one.

## Performance policy

The rootfs does not start systemd, a system D-Bus daemon, Plasma shell, Linux panel, Linux file manager, portal services, screen locker or hardware discovery daemons. WirePlumber uses its policy-only profile, so it only links the AnLand virtual audio nodes and Wine Pulse streams.

The Wine/Hangover runtime prefers Android NTSync when `/dev/ntsync` exists and falls back to ESYNC otherwise. Wine debug output, menu builder, Bluetooth driver, Gecko/Mono prompts, animations and unnecessary Windows background services are disabled. Translated application launches prefer the SDM660 performance cluster, while the always-visible Wine shell remains unpinned so idle work can stay cheap.

## Why KWin remains

Winlator can omit a Linux compositor because its Android application contains its own X server, renderer, input stack and audio components. Droidspaces currently exposes display/input/audio through the repository's AnLand KWin backend, so removing KWin would also remove that Android bridge. The WinLite solution therefore compiles KWin down to the bridge role rather than shipping a KDE desktop.
