Xiaomi Mi Pad 4 Droidspaces RootFS

Default user: user
Default password: 1234
Desktop: KDE Plasma Minimal on Anland Wayland
Locale: Simplified Chinese (zh_CN.UTF-8)

Required Arch container settings are in container.config. With the current
Droidspaces-OSS runtime, set `enable_anland=1` and do not manually bind
`/data/local/tmp/display_daemon.sock`; Droidspaces creates a per-container
Anland socket and exposes it inside the container as `/run/display.sock`.
For KernelSU/ReKSU enforcing mode, install `mi-pad4-sepolicy.rule` as the
module's `sepolicy.rule`; it contains no `permissive` rule.
Import this Arch rootfs into Droidspaces, apply container.config, then open
the Anland Android app.
Audio is provided by Anland and the PipeWire/PulseAudio compatibility stack.
Firefox is source-built for Clover. H.264/HEVC frames pass directly from
msm_vidc ION DMABUFs to WebRender; its legacy-KGSL retire wait prevents decoder
buffer reuse before GPU sampling completes.

This profile installs patched systemd 257 as PID 1. Set
SYSTEMD_DROIDSPACES_COMPAT=1 (already exported by droidspaces-init) to disable
cgroup hierarchy management and unit sandboxing unavailable on Android 4.4;
service supervision, dependencies, restart handling and D-Bus remain enabled.
