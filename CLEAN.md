# clean branch architecture

`clean` rebuilds the Arch image around a generic framework inspired by the current
`Goldzxcbug/Droidspaces-rootfs-Desktop-builder` Arch layout, while keeping E7G's
Mi Pad 4/Clover work as an explicit device profile instead of global policy.

Baseline reference: Gold commit `1df25ef6a52c10b9915126286d968bbccc233cd4`
(2026-09-07). The component TUI/installers are fetched from that pinned revision;
E7G device-specific patches remain local to this repository.

## Layers

- `Arch.Dockerfile`: generic Arch build and feature switches.
- `scripts/desktops/`: desktop profiles (`kde`, `kde-mobile`).
- `scripts/device-profiles/`: hardware profiles (`generic`, `mi-pad4-clover`).
- `scripts/app-compat/droidspaces-launch-app`: toolkit-neutral Linux Apps launcher.
- `DISPLAY_BACKEND`: `x11` or `anland-wayland`.

The key rule is that device workarounds are not global application environment.
In particular, the Mi Pad 4 legacy ION shim is loaded only by
`droidspaces-anland-kwin`; ordinary applications explicitly drop `LD_PRELOAD`.
Qt is not forced to Wayland, so Qt/XCB and X11-only applications can use XWayland.
The desktop profile also keeps xdg-desktop-portal available for modern apps.

## Mi Pad 4 / Clover

`DEVICE_PROFILE=mi-pad4-clover` retains the SDM660/Adreno 512 Android-4.4-kernel
compatibility path: legacy ION translation, KGSL/dma-buf/native-fence compositor
environment, E7G's Clover Anland KWin/XWayland backend, old-kernel KIO support,
and the existing memory/I/O/network tuning. These changes are installed only
when the profile is selected.

The old `mi-pad4-desktop.service` global `pkill` lifecycle is intentionally not
used by the clean profile. Full desktop autostart is supervised by the generic
`desktop-session.service`; Linux Apps use independent Anland sessions.

## WSLg / shared compositor

WSLg V2, `ANLAND_MULTIWINDOW`, shared-KWin session management, and the associated
release/test workflow are intentionally outside the clean architecture. The
branch stays on normal Anland + XWayland while Anland v6 prepares native support
for that functionality. Do not add a second shared-compositor implementation to
this branch in the meantime.

## Examples

Generic KDE/Anland:

```sh
docker buildx build --platform linux/arm64 -f Arch.Dockerfile \
  --build-arg DESKTOP=kde \
  --build-arg DISPLAY_BACKEND=anland-wayland \
  --build-arg DEVICE_PROFILE=generic .
```

Mi Pad 4/Clover (requires the known-good Mi Pad 4 Mesa artifacts when Mesa is
enabled):

```sh
docker buildx build --platform linux/arm64 -f Arch.Dockerfile \
  --build-arg DESKTOP=kde \
  --build-arg DISPLAY_BACKEND=anland-wayland \
  --build-arg DEVICE_PROFILE=mi-pad4-clover .
```

For a Chromium/Electron application on a legacy kernel where user namespaces
are unavailable, the compatibility launcher supports an explicit per-launch
fallback via `DROIDSPACES_CHROMIUM_NO_SANDBOX=1`. It is deliberately not enabled
globally.
