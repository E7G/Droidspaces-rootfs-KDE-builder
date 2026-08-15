// Mi Pad 4 / Anland defaults. The legacy Clover KGSL path makes Firefox's
// WebRender renderer spin on an otherwise idle Wayland surface and can flash
// the panel. Keep GPU acceleration for KWin and V4L2-M2M video, but use the
// low-power basic Firefox compositor by default.
pref("gfx.webrender.all", false);
pref("gfx.webrender.max-partial-present-rects", 0);
pref("gfx.webrender.allow-partial-present-buffer-age", false);
pref("gfx.webrender.force-partial-present", false);
pref("gfx.webrender.compositor", false);
pref("gfx.webrender.compositor.force-enabled", false);
pref("widget.dmabuf.enabled", false);
pref("widget.dmabuf-feedback.enabled", false);
