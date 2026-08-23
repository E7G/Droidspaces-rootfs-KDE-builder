Mi Pad 4 WinLite RootFS
=======================

用途：在 Clover / Droidspaces / Anland 中以尽可能低的常驻占用运行 x86、x64 Windows 应用。

核心：
- Arch Linux ARM64
- patched KWin Anland + KGSL Mesa
- Hangover ARM64EC/FEX（x64）+ wowbox64（x86）
- Wine Wayland 作为高性能直出路径
- Wine explorer shell（Xwayland）提供开始菜单、任务栏、托盘和桌面
- 不安装 LXQt Panel、PCManFM-Qt、Plasma、Firefox、Dolphin、Baloo、Portal
- 内置 droidspaces-tini PID 1，无 systemd 服务管理器

默认界面：
- 启动后直接进入 Wine 自带 shell desktop。
- Wine 桌面上的 Windows 文件夹映射到 /tmp/droidspaces-home/Windows。
- 从 Wine 桌面双击 EXE 即可在同一桌面/任务栏中运行。

命令：
- winrun 程序.exe              最快路径，直接 Wine Wayland，适合游戏/高性能应用
- winrun --desktop 程序.exe    在 Wine shell desktop 内启动，方便任务栏管理
- winrun --shell               重新打开 Wine shell desktop
- winrun --winecfg             打开 Wine 设置
- MSI 同样支持：winrun setup.msi

默认持久目录：/tmp/droidspaces-home/.wine-winlite
默认文件目录：/tmp/droidspaces-home/Windows
默认用户环境：user（Droidspaces 旧内核容器仍由 root UID 托管会话）
