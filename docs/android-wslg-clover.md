# Clover Android WSLg / WinLite profile

`Arch-WinLite.Dockerfile` is the Windows-GUI profile for Xiaomi Pad 4
(Snapdragon 660/Adreno 512). It packages Hangover (arm64ec + FEX), Wine
Wayland, patched KWin, KGSL Mesa and the Anland session supervisor.

## Build

Run the repository's **Build Arch Mi Pad 4 RootFS** workflow and select the
WinLite profile. Import the resulting `.tar.xz` into Droidspaces with hardware
access enabled. The image contains `/usr/local/bin/winrun` and
`/usr/local/bin/winlite-session`.

## Runtime

```sh
droidspaces --name=winlite --rootfs=/path/to/rootfs \
  --anland --gpu --privileged=noseccomp start
droidspaces --name=winlite run /usr/local/bin/winlite-session
droidspaces --name=winlite run /usr/local/bin/winrun /sdcard/Download/app.exe
```

The profile requires a kernel exposing PID/UTS/IPC namespaces and Anland's
virtual DRM/DMABUF path. On the unmodified 4.19 clover kernel these namespace
checks fail, so this image cannot be started there until a compatible kernel is
flashed. Termux:X11 + proot is the fallback, but it is not equivalent to the
isolated WSLg path.

