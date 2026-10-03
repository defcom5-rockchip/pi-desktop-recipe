# HDMI0 "coma" + 4K@120 hang — root-cause notes and a staged (NOT shipped) patch

Staged 2026-09-24. Nothing here is in the Plaid kernel. With patch 0009 (FRL modes hidden unless
`rockchipdrm.allow_frl=1`) neither bug is reachable in normal use; this is the path to a real fix.

## Bug 1 — the coma: PHY off under a live CRTC (black screen, board alive)

Verified from the vendor source (rk-6.1-rkr7.2 @ c0600eeee5f9):
- debugfs `hdmi0/status` printing only `PHY: disabled` means `hdmi->disabled == true`; no hardware is read.
- On a sink HPD-low, `dw_hdmi_qp_handle_hpd()` AVMUTEs, powers the PHY off and sets `disabled` — but leaves
  the CRTC/VOP scanning out (vendor "keep output" design). On HPD-high it re-powers the PHY.
- The glue's `repo_hpd_event()` only calls `handle_hpd()` when `drm_helper_hpd_irq_event()` reports a change,
  and that reports a change only if its OWN detect bumped the connector's epoch counter.
- If anything else probes the connector between the low and the high edge (fbdev client, mutter
  GETCONNECTOR), the high edge looks like "no change" → `handle_hpd(true)` is never called → PHY stays off.
- `dw_hdmi_connector_atomic_check()` won't force a modeset while `disabled`, so a same-mode commit or VT switch
  does nothing. Only a real disable→enable (DPMS off/on, mode change, reboot) re-powers the PHY.

Inferred (fits every symptom, not yet observed directly): the sink toggles HPD during its own re-init.
Smoking gun to look for: drm.debug=0x4 + `file dw_hdmi_qp-rockchip.c +p` →
`[CONNECTOR:..:HDMI-A-1] Same epoch counter N` right after an HPD-high irq.

Recovery without reboot (measured 2026-09-24 19:32): DPMS off/on through the active compositor
(`busctl --user set-property org.gnome.Mutter.DisplayConfig /org/gnome/Mutter/DisplayConfig
org.gnome.Mutter.DisplayConfig PowerSaveMode i 3`, wait 3 s, `… i 0`; at the greeter as its dynamic uid).

Patch `0001-dw_hdmi_qp-always-report-debounced-hpd-level.patch`: hand the debounced level to
`handle_hpd()` / `cec_set_hpd()` unconditionally (both idempotent), skip outputs whose detect doesn't follow
the pin, and log the PHY power transitions. TMDS path only (FRL early-return untouched). Compiles clean
(gcc 15.2, W=1). NOT runtime-tested — it changes the 60 Hz path, which works today, so it must be soaked
before it goes near an image. Open: keep `cec_set_hpd` under `if (change)` to avoid one EDID read per HPD-high?

## Bug 2 — 4K@120: board hard-hangs after DPMS-off + the sink's standby HPD toggle

HPD handling itself is safe at FRL (GRF-only IRQ, `handle_hpd` returns early above 600 MHz, controller
clocks and PD_VO1 held for the device lifetime). Prime suspect (inference from code):
- The HDPTX PHY uses runtime PM; its runtime-suspend gates PCLK_HDPTX0 (plain gate, not critical).
- `rk_hdptx_phy_configure_ffe()` writes LANE registers — FRL-only — from `phy_configure()`, which
  `dw_hdmi_rockchip_encoder_atomic_check()` calls on EVERY atomic check (incl. TEST_ONLY) without taking a
  runtime-PM reference.
- After a DPMS-off the PHY is powered off; the sink's HPD toggle → uevent → mutter re-evaluates → atomic_check →
  FFE register writes on an unclocked APB → SoC bus hang. Matches: blank-then-hang ~15 s later, no user input.
- Two lesser candidates (A: `rk_hdptx_phy_disable()` via link-clk unprepare after phy_power_off; C: PLL config
  via `link_clk_set(true)` before `phy_power_on`) would also bite in TMDS, which doesn't hang — calibration.

Cheap discriminators on the box (root), after a DPMS-off at 4K@120 vs 4K@60:
`cat /sys/bus/platform/devices/fed60000.phy/power/runtime_status` and
`cat /sys/kernel/debug/clk/pclk_hdptx0/clk_enable_count` — "suspended"/0 at 120 points at B.
Fix direction for B: store ffe_lv/ffe_mode in configure and apply them on the power-on path (write
immediately only under `pm_runtime_get_if_in_use()`); for A/C wrap the register sequences in
`pm_runtime_resume_and_get()`. Vendor-only code (mainline's HDPTX driver has no FFE writes; FRL isn't upstream).
