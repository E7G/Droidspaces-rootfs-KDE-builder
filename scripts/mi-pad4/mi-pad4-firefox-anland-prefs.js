// Mi Pad 4 / Anland defaults. The Android BufferQueue recycles implicit-linear
// buffers and does not preserve untouched damage regions like a normal Wayland
// compositor. Keep Firefox on GPU/WebRender, but submit complete EGL frames.
pref("gfx.webrender.all", true);
pref("gfx.webrender.max-partial-present-rects", 0);
pref("gfx.webrender.allow-partial-present-buffer-age", false);
pref("gfx.webrender.force-partial-present", false);
pref("gfx.webrender.compositor", false);
pref("gfx.webrender.compositor.force-enabled", false);
pref("widget.dmabuf.enabled", true);
pref("widget.dmabuf-feedback.enabled", false);
