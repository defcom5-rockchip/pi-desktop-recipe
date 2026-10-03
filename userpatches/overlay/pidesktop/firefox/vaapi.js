// Pi-Desktop: Firefox hardware video decode through the Rockchip VA-API driver.
// Mirrors 2.0.x /usr/lib/firefox/defaults/pref/vaapi.js, plus:
//  - HEVC on (the driver decodes HEVC Main/Main10 in hardware)
//  - AV1 OFF: the VPU has no AV1 path, and with AV1 enabled YouTube serves AV1 streams that fall to
//    software (8 cores at 70-90% CPU). With it off YouTube serves VP9, which is hardware-decoded.
pref("media.ffmpeg.vaapi.enabled", true);
pref("media.hardware-video-decoding.force-enabled", true);
pref("media.hevc.enabled", true);
pref("media.av1.enabled", false);
