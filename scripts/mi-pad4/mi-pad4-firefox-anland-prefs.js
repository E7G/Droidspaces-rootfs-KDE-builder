// Mi Pad 4 / Anland defaults. Keep Firefox page/video composition on WebRender
// but disable direct window DMABUF export; plasmashell owns the stable panel
// path separately.
pref("gfx.webrender.all", true);
pref("gfx.webrender.enabled", true);
pref("layers.acceleration.force-enabled", true);
pref("layers.acceleration.disabled", false);
pref("gfx.webrender.max-partial-present-rects", 0);
pref("gfx.webrender.allow-partial-present-buffer-age", false);
pref("gfx.webrender.force-partial-present", false);
pref("gfx.webrender.compositor", false);
pref("gfx.webrender.compositor.force-enabled", false);
pref("widget.dmabuf.enabled", true);
pref("widget.dmabuf-export.force-enabled", false);
pref("widget.dmabuf-feedback.enabled", false);
pref("widget.dmabuf-webgl.enabled", false);
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
pref("media.mediasource.vp9.enabled", true);
pref("media.hardware-video-decoding.enabled", true);
pref("media.hardware-video-decoding.force-enabled", true);
pref("media.ffvpx-hw.enabled", true);
pref("media.rdd-ffvpx.enabled", true);
pref("media.prefer-non-ffvpx", false);
pref("media.ffmpeg.vaapi.enabled", false);
pref("media.rdd-ffmpeg.enabled", true);
pref("media.rdd-vpx.enabled", true);
// This switch applies to audio as well as video. AAC needs FFmpeg software
// decoding even while H.264/HEVC use the preferred V4L2/GPU decoder.
pref("media.ffmpeg.disable-software-fallback", false);
pref("media.decoder.recycle.enabled", true);
pref("media.ffvpx.enabled", true);
pref("browser.ml.enable", false);
pref("toolkit.telemetry.enabled", false);
pref("datareporting.healthreport.uploadEnabled", false);
