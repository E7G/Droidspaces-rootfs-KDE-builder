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
