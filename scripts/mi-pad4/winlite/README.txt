Mi Pad 4 WinLite RootFS
=======================

用途：把 Droidspaces RootFS 收敛成类似 Winlator 的 Windows 容器运行时，以尽可能低的常驻占用运行 x86/x64 Windows 应用。

运行模型：
- Android 侧仍由 Droidspaces/AnLand 提供容器、显示 socket、输入、音频与硬件访问。
- Linux 侧没有 Plasma/LXQt/Panel/文件管理器；KWin 仅作为当前仓库 AnLand 后端的最小显示/输入/音频桥。
- KWin 启动 Xwayland 后，直接运行 Wine explorer.exe /desktop=shell，Windows Explorer 自己提供桌面、开始菜单、任务栏和托盘。
- 该 UI 模型与 Winlator 当前容器的 Wine Explorer 虚拟桌面思路一致，但不把 Winlator APK/Java XServer 整套塞进 RootFS。

核心：
- Arch Linux ARM64 最小运行环境
- patched KWin AnLand bridge + KGSL Mesa / Adreno 512
- WinLite 魔改 Hangover 11.9：ARM64EC/FEX（x64）+ wowbox64（x86）
- Android/Droidspaces 专用 NTSync：运行时优先 /dev/ntsync，无设备时自动回退 ESYNC
- Wine 固定 X11 驱动，经 Xwayland 进入 AnLand；不再探测/加载 Wine Wayland 驱动
- 无 systemd、无 system D-Bus、无 Linux 桌面 shell、无 Portal、无屏幕锁

Winlator 风格容器：
- 每个容器拥有独立 Wine Prefix：~/.winlite/containers/<名称>/.wine
- 当前容器记录在 ~/.winlite/active-container
- 旧版 ~/.wine-winlite 首次启动会自动无损迁移为 default 容器
- ~/Windows 作为所有容器共享文件目录，并映射为 G: 与桌面 Windows 文件夹
- 新容器采用惰性初始化：第一次进入/运行应用时才执行 wineboot

容器命令：
- wincontainer current          查看当前容器
- wincontainer list             列出容器
- wincontainer create game      创建 game 容器
- wincontainer use game         切换下次图形会话进入 game
- wincontainer path game        查看容器目录
- wincontainer prefix game      查看 Wine Prefix 路径
- wincontainer delete game      删除非当前容器

性能/功耗优化：
- WINEDEBUG=-all，关闭常规 Wine 日志 I/O。
- MESA_DEBUG=silent、MESA_NO_ERROR=1、mesa_glthread=true、vblank_mode=0。
- 禁用 winemenubuilder.exe、winebth.sys、Gecko/Mono 自动加载提示。
- Prefix 初始化加锁；字体 fc-match、桌面扫描和注册表调优只在版本升级时执行一次，不再每次启动应用重复跑。
- 默认应用负载调度到 SDM660 CPU 4-7 性能簇；常驻 Wine shell 不绑大核，空闲时让调度器降功耗。
- WirePlumber 不探测 ALSA/蓝牙/MIDI/V4L2/libcamera，也不接入 logind/system D-Bus；只保留 AnLand 虚拟音频节点的策略管理。
- 删除 Wine Wayland 驱动、开发头文件、文档、man/info、locale 源数据库、静态库和无用语言目录。
- 不安装 Proton/Steam Runtime、LXQt Panel、PCManFM-Qt、Plasma Workspace、Firefox、Dolphin、Baloo、Portal。

Wine 后台服务：
- 极限模式默认禁用 BITS、Eventlog、HTTP、LanmanServer、Smart Card、Schedule、Spooler、StiSvc、TermService、WMI、Windows Update、Wine Bluetooth。
- 为避免把常见软件/安装器直接砍坏，仍保留 RpcSs、PlugPlay、NDIS、MSI Server 与 FontCache。

字体：
- Latin：Liberation Sans / Serif / Mono，覆盖 Arial、Segoe UI、Tahoma、Times New Roman、Courier New。
- 中文：WenQuanYi Zen Hei，覆盖微软雅黑、Microsoft YaHei、宋体、SimSun、新宋体、黑体、SimHei。
- Wine 注册表和 Fontconfig 双重替换，C:\Windows\Fonts 使用零拷贝软链接。
- 默认 144 DPI + 灰阶抗锯齿，适合 Mi Pad 4 高 DPI 与旋转显示。

默认界面与命令：
- 启动后直接进入 Wine Explorer shell desktop。
- winrun 程序.exe              默认在同一 Wine 桌面/任务栏中运行（Winlator 风格）
- winrun --direct 程序.exe     直接 X11 窗口，跳过 Explorer desktop 包装
- winrun --shell               重新打开 Wine Explorer desktop
- winrun --winecfg             Wine 设置
- winrun --sync-info           查看当前容器、Prefix、NTSync/ESYNC
- winrun --container game ...  临时指定容器运行命令
- MSI：winrun setup.msi

默认容器目录：/tmp/droidspaces-home/.winlite/containers/default
共享文件目录：/tmp/droidspaces-home/Windows
默认用户环境：user（Droidspaces 旧内核容器仍由 root UID 托管会话）
