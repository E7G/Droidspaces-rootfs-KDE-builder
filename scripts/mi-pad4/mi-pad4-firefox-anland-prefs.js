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
// Keep the normal browser usable, but avoid speculative processes and large
// disk caches competing with Plasma on the shared 4 GiB Android host.
pref("dom.ipc.processCount", 1);
pref("dom.ipc.processPrelaunch.enabled", false);
pref("browser.tabs.unloadOnLowMemory", true);
pref("browser.sessionhistory.max_total_viewers", 2);
pref("browser.cache.disk.enable", false);
pref("browser.cache.disk.capacity", 0);
pref("browser.cache.memory.capacity", 16384);
pref("browser.sessionstore.interval", 300000);
pref("browser.sessionstore.max_tabs_undo", 3);
pref("network.http.max-connections", 64);
pref("network.http.max-persistent-connections-per-server", 6);
pref("media.av1.enabled", false);
pref("browser.ml.enable", false);
pref("toolkit.telemetry.enabled", false);
pref("datareporting.healthreport.uploadEnabled", false);
