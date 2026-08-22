Mi Pad 4 WinLite RootFS
=======================

用途：在 Clover / Droidspaces / Anland 中运行 x86、x64 Windows 应用。

核心：
- Arch Linux ARM64
- patched KWin Anland + KGSL Mesa
- Hangover ARM64EC/FEX（x64）+ wowbox64（x86）
- Wine Wayland，Xwayland 仅兼容回退时按需启动
- LXQt Panel + PCManFM-Qt，无 Plasma、Firefox、Dolphin、Baloo、Portal
- 内置 droidspaces-tini PID 1，无 systemd 服务管理器

用法：
1. 把 EXE/MSI 放到 Windows 目录。
2. PCManFM-Qt 双击，或终端执行：winrun 程序.exe
3. Wine 设置：菜单中打开“Wine 设置”。

默认持久目录：/tmp/droidspaces-home/.wine-winlite
默认用户环境：user（Droidspaces 旧内核容器仍由 root UID 托管会话）
