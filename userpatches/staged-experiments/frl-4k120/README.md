# 4K@120 FRL experiment kit (staged 2026-09-24 — NOT in the build; move into place deliberately)

Context: two 4K@120 black screens (09-22 18:29, 09-24 08:27) — after 1–2 h the sink stops answering DDC/SCDC
(`i2c read time out`), link lost; a live modeset on that state hard-hung the board once. dri-devel thread
"ACLK_VOP pinned at 500 MHz starves DP 4K120 on RK3588" (Aug 2026): on MAINLINE the VOP AXI clock is stuck at 500 MHz
and 4K120 underflows (POST_BUF_EMPTY storm). On our VENDOR kernel the aclk already runs 750 MHz in "advanced mode"
(measured on the test board at 4K60; hdisplay > 2560 or linedur < 7.5 us selects it) — but underflow REPORTING is off
(DT flag absent), so our logs cannot exclude it.

1. `rk3588-vop-report-post-buf-empty.dts` (+ .dtbo) — overlay adding `rockchip,report-post-buf-empty` to /vop@fdd90000.
   Install on the board:  sudo armbian-add-overlay rk3588-vop-report-post-buf-empty.dts   (reboot; remove via armbianEnv user_overlays)
2. `0001-drm-rockchip-dw_hdmi_qp-optional-cap-on-the-FRL-per-.patch` — module param `frl_max_rate_per_lane`
   (default 0 = unchanged). Built into rockchipdrm → runtime: echo 8 | sudo tee /sys/module/rockchipdrm/parameters/frl_max_rate_per_lane
   before switching to 120 Hz (8 = 32G, the floor for 4K120 8-bit). Needs a kernel build (copy to kernel/rk35xx-vendor-6.1/ as 0007).
   Not compile-tested yet. Worktree branch frl-max-rate-param @ eb2e3eb2dd73.

Run plan: overlay on → 4K@120 at default 40G until failure (watch POST_BUF_EMPTY vs the first i2c timeout) →
then 32G cap → same. Also swap in a certified Ultra High Speed (48G) cable for one run. Stay at 4K60 otherwise.

## 0002 — FLT_update poll interval (added 2026-09-24)

Differential found: the Riek-fork kernel (BSP 6.1.75) ran this monitor (XHS XR32UMH) + cable at
4K@120 over FRL (`flt success`, dclk 1082890000 — same mode/link as Plaid) and never polled the
sink after training (`hdmi_start_flt()` returns). rkr7.2 `dw_hdmi_qp_flt_ltsp()` reads SCDC_UPDATE_0
over DDC every 100 ms forever — and every Plaid 120 Hz incident starts with DDC `i2c read time out`.

Knob (built-in object, runtime-writable, default = unchanged):
    /sys/module/dw_hdmi_qp/parameters/frl_update_poll_ms   100 (default) | 250 (spec max) | 1000 | 0 (= fork: don't poll)
    cmdline form: dw_hdmi_qp.frl_update_poll_ms=0
Takes effect on the next poll tick — no modeset, no reboot. With 0 the dclk/disconnect exits still run.
Trade-off at 0: a sink-requested FLT re-train (FLT_update bit 5) is ignored, exactly like the fork.

Test order: 120 Hz with `frl_update_poll_ms=0` for >3 h incl. the VLC/Firefox load that failed before
(failures came at 14 min / 2 h / 3 h). Clean → try 250. Still fails at 0 → polling is not it; next is
0001 `rockchipdrm.frl_max_rate_per_lane=8` (32G). Both compile-tested for arm64 against test2's
/boot/config (a local O= build directory), branch frl-max-rate-param @ a4878d1d17c1.
