// Plaid Pi: Firefox hardware video decode through the Rockchip VA-API driver.
// Mirrors 2.0.x /usr/lib/firefox/defaults/pref/vaapi.js, plus:
//  - HEVC on (the driver decodes HEVC Main/Main10 in hardware)
//  - AV1 ON since Plaid Pi 5.0: rockchip-vaapi 3.0.0 "Plaid Number Nine" decodes AV1 Main 8/10-bit on the VPU,
//    and libpidesktop-ffmali (loaded by the launcher) lets the unmodified Firefox import both depths (1080p clips
//    tested 2026-10-12).
//    (Up to 4.x it was off: the driver had no AV1 path and YouTube's AV1 streams fell to software.)
pref("media.ffmpeg.vaapi.enabled", true);
pref("media.hardware-video-decoding.force-enabled", true);
pref("media.hevc.enabled", true);
pref("media.av1.enabled", true);
// libpidesktop-ffmali copies some planes into textures Firefox only samples; these two settings would make Firefox
// render into them instead (copy-mode video, native compositor), so they are fixed here and locked in policies.json.
pref("media.ffmpeg.vaapi.force-surface-zero-copy", 1);
pref("gfx.webrender.compositor", false);
// 4K60 AV1 on the VPU without drops (2026-10-15, Firefox 157/158 + rockchip-vaapi 3.5.0): a deeper hardware frame queue
pref("media.video-queue.hw-accel-size", 10);
