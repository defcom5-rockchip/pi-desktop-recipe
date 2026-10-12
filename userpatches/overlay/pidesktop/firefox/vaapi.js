// Pi-Desktop: Firefox hardware video decode through the Rockchip VA-API driver.
// Mirrors 2.0.x /usr/lib/firefox/defaults/pref/vaapi.js, plus:
//  - HEVC on (the driver decodes HEVC Main/Main10 in hardware)
//  - AV1 ON since Plaid Pi 5.0: rockchip-vaapi 3.0.0 "Plaid Number Nine" decodes AV1 Main 8/10-bit on the VPU.
//    (Up to 4.x it was off: the driver had no AV1 path and YouTube's AV1 streams fell to software.)
//    With the stock Firefox the 10-bit profiles stay hidden by the launcher (RKVA_HIDE_10BIT) until the
//    Mali 10-bit import fix lands in Firefox; 10-bit then decodes in software with correct colours.
pref("media.ffmpeg.vaapi.enabled", true);
pref("media.hardware-video-decoding.force-enabled", true);
pref("media.hevc.enabled", true);
pref("media.av1.enabled", true);
