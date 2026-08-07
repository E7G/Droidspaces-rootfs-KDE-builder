Xiaomi Mi Pad 4 Droidspaces RootFS

Default user: user
Default password: 1234
Desktop: KDE Plasma Minimal on Anland Wayland
Locale: Simplified Chinese (zh_CN.UTF-8)

Required container settings are in container.config.
For KernelSU/ReKSU enforcing mode, install `mi-pad4-sepolicy.rule` as the
module's `sepolicy.rule`; it contains no `permissive` rule.
Start the existing Ubuntu container, then open the Anland Android app.
Audio is provided by Anland and the PipeWire/PulseAudio compatibility stack.
Firefox uses msm_vidc hardware decoding for validated H.264 and HEVC streams.

This profile installs patched systemd 257 as PID 1. Set
SYSTEMD_DROIDSPACES_COMPAT=1 (already exported by droidspaces-init) to disable
cgroup hierarchy management and unit sandboxing unavailable on Android 4.4;
service supervision, dependencies, restart handling and D-Bus remain enabled.
