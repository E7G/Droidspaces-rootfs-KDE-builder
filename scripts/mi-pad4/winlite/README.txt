Mi Pad 4 WinLite RootFS
=======================

用途：在 Clover / Droidspaces / Anland 中以尽可能低的常驻占用运行 x86、x64 Windows 应用。

核心：
- Arch Linux ARM64
- patched KWin Anland + KGSL Mesa
- WinLite 魔改 Hangover 11.9：ARM64EC/FEX（x64）+ wowbox64（x86）
- Android/Droidspaces 专用 NTSync：编译时内置 UAPI，运行时检测 /dev/ntsync
- 无 /dev/ntsync 时自动回退 ESYNC，不启用 FSYNC
- Wine Wayland 作为高性能直出路径
- Wine explorer shell（Xwayland）提供开始菜单、任务栏、托盘和桌面
- 不安装 Proton/Steam Runtime、LXQt Panel、PCManFM-Qt、Plasma、Firefox、Dolphin、Baloo、Portal
- 内置 droidspaces-tini PID 1，无 systemd 服务管理器

Proton 风格精简优化：
- 保留 Proton 思路里对普通 Wine 也有价值、且无需额外 Runtime 的部分。
- WINEDEBUG 默认关闭，减少日志和 I/O。
- 禁用 winemenubuilder.exe，减少后台菜单扫描和唤醒。
- 禁用 winebth.sys；Android WinLite 不需要 Wine 蓝牙驱动常驻。
- 提供轻量 G: 游戏盘映射，直接指向 /tmp/droidspaces-home/Windows。
- Windows 应用默认调度到 SDM660 性能簇，Wine shell 自身不绑大核，空闲时可降功耗。
- 不为了这些优化引入 UMU、pressure-vessel、DXVK/VKD3D 或 Steam Runtime。

字体：
- Latin：Liberation Sans / Serif / Mono，覆盖 Arial、Segoe UI、Tahoma、Times New Roman、Courier New。
- 中文：WenQuanYi Zen Hei，覆盖微软雅黑、Microsoft YaHei、宋体、SimSun、新宋体、黑体、SimHei。
- Wine 注册表和 Fontconfig 双重替换。
- C:\Windows\Fonts 里创建零拷贝字体软链接，兼容直接按字体文件名探测的 Windows 软件。
- 默认 144 DPI，并使用适合平板旋转的灰阶抗锯齿，避免 ClearType RGB/BGR 色边。
- 已有 Wine prefix 会通过版本标记自动补上新的字体/性能设置，不需要手工删 prefix。

默认界面：
- 启动后直接进入 Wine 自带 shell desktop。
- Wine 桌面上的 Windows 文件夹映射到 /tmp/droidspaces-home/Windows。
- G: 同样映射到该目录。
- 从 Wine 桌面双击 EXE 即可在同一桌面/任务栏中运行。

命令：
- winrun 程序.exe              最快路径，直接 Wine Wayland，适合游戏/高性能应用
- winrun --desktop 程序.exe    在 Wine shell desktop 内启动，方便任务栏管理
- winrun --shell               重新打开 Wine shell desktop
- winrun --winecfg             打开 Wine 设置
- winrun --sync-info           查看当前使用 NTSync 还是 ESYNC
- MSI 同样支持：winrun setup.msi

默认持久目录：/tmp/droidspaces-home/.wine-winlite
默认文件目录：/tmp/droidspaces-home/Windows
默认用户环境：user（Droidspaces 旧内核容器仍由 root UID 托管会话）
