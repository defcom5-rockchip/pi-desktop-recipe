# Plaid Pi 5.0 — build recipe

This repository is the complete build recipe for **Plaid Pi 5.0** (formerly Pi-Desktop; 4.5 was built but never
published), a desktop Linux image for the **Orange Pi 5B** (Rockchip RK3588S). It is an
[Armbian build framework](https://github.com/armbian/build) `userpatches/` layer: Ubuntu 26.04 LTS "Resolute" with
GNOME 50 on the Rockchip vendor 6.1 kernel — Armbian's `rk-6.1-rkr7.2` tree merged with upstream stable Linux 6.1.189
(kernel version string `6.1.189-vendor-rk35xx`) — plus the Plaid Pi additions:

- the 4K@120 Hz HDMI 2.1 (FRL) kernel work, AFBC flicker fix, WPA3 fix for the AP6275P WiFi, and the fixes that
  keep Armbian's out-of-tree WiFi drivers building on 6.1.189 (`userpatches/kernel/rk35xx-vendor-6.1/`, 16 patches),
- the ARM Mali G610 userspace driver (libmali, wayland-gbm) with a small `EGL_EXT_device_query` shim in the
  libmali hook, and `libpidesktop-ffmali`, a library the Firefox launcher loads so the unmodified Firefox, once the
  user installs it, runs on the GPU and decodes 8- and 10-bit video on the VPU,
- hardware video decode (H.264, HEVC, VP9, AV1) in Chromium, mpv and the first-click-installed browsers (Rockchip
  MPP with Plaid Pi's AV1 and VP9 patches, RGA, rockchip-vaapi 3.5.0), and a rebuilt mpv that draws zero-copy
  8- and 10-bit video correctly on the Mali driver,
- PipeWire 1.6.9 / WirePlumber 0.5.17 with a hi-res audio lane, real-time scheduling and a working 3.5 mm jack,
  and a GStreamer FLAC seek fix for Rhythmbox,
- a screensaver service in place of screen blanking, with a patched GNOME Settings Power panel,
- Pro Updates 1.5.0, the update window,
- the Plaid look (wallpaper, terminal palette, fastfetch logo, login-screen wordmark), first-click installers for
  large apps, Bluetooth boot-race fixes, persistent journal, and a few dozen smaller things, all documented inline
  in `userpatches/customize-image.sh`.

Everything that goes into the image either is in this repository, is fetched from a public package archive
at build time, or is a pre-built input attached to a GitHub release of this repository (see
[Build inputs](#build-inputs) and [SOURCES.md](SOURCES.md)).

## Repository layout

| Path | What it is |
| --- | --- |
| `userpatches/` | The Armbian `userpatches/` directory, as used for the release build. Copy it into an Armbian build checkout as-is. |
| `userpatches/config-pidesktop3.conf` | Board/branch/release selection plus the framework hooks (pinned kernel and U-Boot sources, kernel-config hooks, apt policy, armbian-config removal, version hand-over). |
| `userpatches/customize-image.sh` | The Plaid Pi layer: runs as root inside the image chroot at the end of Armbian's customize step. Every step logs `I: [pi-desktop]` / `W: [pi-desktop]`. |
| `userpatches/overlay/pidesktop/` | Files installed into the image by `customize-image.sh` (bind-mounted at `/tmp/overlay` during the build). |
| `userpatches/overlay/pidesktop/branding/` | The Plaid Pi logo (SVG, PNG renders, Plymouth images, login-screen wordmark) and the scripts that generate them. |
| `userpatches/overlay/pidesktop/fastfetch/` | The tartan terminal logo `plaid.ans`, its generator `plaid_logo.py` and the fastfetch config. |
| `userpatches/overlay/pidesktop/firefox/ffmali/` | `libpidesktop-ffmali`: source (`libpidesktop-ffmali.c`), `build.sh`, README and the board probe. The built `libpidesktop-ffmali.so.1` is a build input. |
| `userpatches/overlay/pidesktop/debs/` | The pre-built `.deb` inputs (`gcc/`, `gst-plugins-good/`, `media/`, `pipewire/`, `pro-updates/`, `rhythmbox/` and the libmali package); fetched by `fetch-inputs.sh`, not in git. |
| `userpatches/kernel/rk35xx-vendor-6.1/` | The 16 kernel patches applied on top of the pinned kernel source. |
| `userpatches/linux-rk35xx-vendor.config` | The kernel config fed to the build (Armbian's `config/kernel/linux-rk35xx-vendor.config` plus `RT_GROUP_SCHED` off and the lockup detector on). Two hooks in the config file adjust it further: `armbian_kernel_config__zz_pidesktop_no_rt_group_sched` keeps the framework from switching `RT_GROUP_SCHED` back on; `armbian_kernel_config__zz_pidesktop_hardening` turns on Yama, hardened usercopy, slab freelist hardening/randomisation and `init_on_alloc`, and builds the Mali kernel driver without its debug options. |
| `userpatches/bootenv/rk35xx.txt` | Boot environment (`cma=512M`, FRL poll off, `allow_frl=1`). |
| `userpatches/gcc/` | The gnome-control-center patch and the script that rebuilds the `+pd3.4` packages. |
| `userpatches/rhythmbox/` | The Rhythmbox 3.5.1 build script and its one patch. |
| `userpatches/mpv/` | The two mpv patches (`patches/`), the build script `build-mpv-deb.sh` that turns Ubuntu's `mpv 0.41.0-2ubuntu4` source into `+pd1`, and the `mpv.conf` it packages. |
| `userpatches/gst-plugins-good/` | The upstream flacparse patch and the script that rebuilds Ubuntu's `gst-plugins-good1.0 1.28.2-2ubuntu0.4` as `+pd1`. |
| `userpatches/staged-experiments/` | Notes and patches from the 4K@120 investigation. Not part of the build (the framework ignores this directory); kept as the record behind kernel patches 0007–0011. |
| `userpatches/INPUTS.sha256` | Checksums of the 36 pre-built inputs, with the path each one belongs at under `userpatches/`. |
| `fetch-inputs.sh` | Downloads the pre-built inputs into place and verifies them. |
| `kernel-config/config-6.1.189-vendor-rk35xx` | `/boot/config-6.1.189-vendor-rk35xx` read from the 5.0 release test board (the config the shipped kernel was actually built with). `config-6.1.172-vendor-rk35xx` is the same for the 4.0 release. |
| `manifest/packages-5.0.tsv` | `dpkg-query -W` of the release test board: every package and version in the image (`packages-4.0.tsv` is the 4.0 list). |
| `manifest/apt-sources-5.0.txt` | `apt-cache policy` of the release test board: the archives and pins the image updates from (`apt-sources-4.0.txt` is the 4.0 list). |
| `SOURCES.md` | Where every rebuilt or binary component comes from and under which licence. |
| `ARTWORK.md` | The Plaid Pi artwork and its licence (CC BY-SA 4.0). |
| `LICENSE`, `LICENSES/` | GPL-3.0 (the recipe) and CC BY-SA 4.0 (the artwork) texts. |

`config-example.conf` and `customize-image.sh.armbian-example` are the framework's own templates and are not used.

## How to build

The image was built natively (not in Docker) on an x86-64 host running Ubuntu 26.04, with the Armbian build
framework at the commit below. Other framework revisions may need adjustments: the recipe hooks into framework
internals (`armbian_kernel_config` option arrays, `apt_find_upstream_package_version_and_download_url`,
`chroot_sdcard`, `custom_apt_repo`) that change over time.

1. Check out the framework at the release commit:

   ```sh
   git clone https://github.com/armbian/build.git armbian-build
   cd armbian-build
   git checkout 1f1ea656b4a875ac27fa9cd0ea6be23e430f34f7   # armbian/build main, 2026-09-21
   ```

2. Put this recipe in place and fetch the pre-built inputs:

   ```sh
   git clone https://github.com/defcom5-rockchip/pi-desktop-recipe.git
   cp -r pi-desktop-recipe/userpatches .          # into the armbian-build checkout
   (cd pi-desktop-recipe && ./fetch-inputs.sh)    # downloads about 93 MB into pi-desktop-recipe/userpatches/…
   cp -r pi-desktop-recipe/userpatches .          # …so copy again, or run fetch-inputs.sh with the copy
   ```

   `fetch-inputs.sh` only writes files listed in `userpatches/INPUTS.sha256`, each verified by SHA-256 before
   it is moved into place. Simplest is to clone this repository, run `./fetch-inputs.sh` inside it, and then
   copy `userpatches/` into the framework checkout once.

3. Build, exactly as the header of `userpatches/config-pidesktop3.conf` says:

   ```sh
   sudo env PREFER_DOCKER=no ./compile.sh pidesktop3
   ```

   The framework downloads the kernel and U-Boot sources, applies the patches, builds the kernel, U-Boot and
   the BSP packages, debootstraps the Ubuntu root filesystem, installs the GNOME desktop, and finally runs
   `customize-image.sh` inside the image. A first build takes a few hours; later builds reuse the cache.

   The kernel source is pinned by the `post_family_config__pidesktop_pinned_sources` hook in the config:
   `KERNELSOURCE` is <https://github.com/defcom5-rockchip/linux-rockchip.git> at commit
   `f3411423c1e9e40340f13e18828e0b31b53d50ce` (`KERNELBRANCH=commit:…`), and U-Boot is pinned likewise. The stock
   framework takes that https URL as it is; `PIDESKTOP_KERNELSOURCE=file:///path/to/clone` works only with a small
   local change to the framework's `lib/functions/general/git-ref2info.sh` (the config comment says so). The
   same hook skips Armbian's `driver_rtw88` step, because its rtw88 backport no longer applies to the 6.1.189 merge;
   kernel patch 0012 carries it refreshed.

4. The image lands in `output/images/`:

   ```
   output/images/Pi-Desktop_26.11.0-trunk_Orangepi5b_resolute_vendor_6.1.189_gnome_desktop.img
   output/images/Pi-Desktop_26.11.0-trunk_Orangepi5b_resolute_vendor_6.1.189_gnome_desktop.img.sha
   output/images/Pi-Desktop_26.11.0-trunk_Orangepi5b_resolute_vendor_6.1.189_gnome_desktop.img.txt
   ```

   (`COMPRESS_OUTPUTIMAGE=sha,img` leaves a raw image plus checksum; the published `.img.zst` is that file
   compressed with `zstd -19`.) The published 5.0 image is `Plaid-Pi-5.0-orangepi5b.img.zst`, 1,486,451,853 bytes,
   SHA-256 `d592a48fadaac293704b1a74fad9e1a3f8c05389eab21d3ee05e2578daeaf6be`. `customize-image.sh` also writes
   `/etc/pi-desktop-manifest.txt` into the image with the key package versions and holds, and prints it in the
   build log.

Build-time switches live in `config-pidesktop3.conf`: `PIDESKTOP_VERSION` is the string shown in
`/etc/os-release`, the MOTD and `/etc/issue`; `PIDESKTOP_GPU_STACK=mesa` builds a control image on stock Mesa
(llvmpipe on this kernel) instead of libmali; `PIDESKTOP_BOARD=orangepi5` selects the Orange Pi 5 instead of
the 5B (the release image is the 5B build).

## Build inputs

36 pre-built files are not in git (`.gitignore` keeps them out): 33 `.deb` packages under
`userpatches/overlay/pidesktop/debs/`, the patched `libmali-hook.so.1.9.0` under `overlay/pidesktop/gpu/`,
`libpidesktop-ffmali.so.1` under `overlay/pidesktop/firefox/ffmali/`, and the screensaver video under
`overlay/pidesktop/usr/share/pi-desktop/screensaver/`; about 93 MB together. They are published as the GitHub
release **`inputs-5.0`** of this repository, and `fetch-inputs.sh` fetches them into place (GitHub stores release
assets with `~` in the name replaced by `.`, so the script requests `pipewire_1.6.9-2.pd31_arm64.deb` and saves it
under its real name). `userpatches/INPUTS.sha256` is in `sha256sum` format, so
`cd userpatches && sha256sum -c INPUTS.sha256` also verifies a populated tree.

What each input is, where it was built from and under which licence is in [SOURCES.md](SOURCES.md). The
packages we rebuilt or built (gnome-control-center, Rhythmbox, PipeWire, WirePlumber, MPP, rockchip-vaapi, mpv,
gst-plugins-good, Pro Updates, libpidesktop-ffmali) are reproducible from the sources named there; the libmali
package is ARM's proprietary driver as packaged by Rockchip and is not built from source.

## Kernel, U-Boot and firmware

- **Kernel**: <https://github.com/defcom5-rockchip/linux-rockchip> at commit
  `f3411423c1e9e40340f13e18828e0b31b53d50ce`. That is [armbian/linux-rockchip](https://github.com/armbian/linux-rockchip)
  branch `rk-6.1-rkr7.2` at `44bbd021d7808cab93d1f2d64c1f092038257576` (Linux 6.1.172, Rockchip BSP release
  rkr7.2) merged with upstream stable `v6.1.189` (merge commit `7b6195db`), plus one commit, "Adapt vendor drivers
  to interface changes in stable 6.1.189" (`f3411423`). On top of it the framework applies Armbian's own
  vendor-kernel patch set (`patch/kernel/rk35xx-vendor-6.1/`) and its driver step, then the 16 patches in
  `userpatches/kernel/rk35xx-vendor-6.1/`, with `userpatches/linux-rk35xx-vendor.config` and the hooks named
  above (the resulting `/boot/config` is in `kernel-config/`). The fork's branch and tag **`pi-desktop-5.0`** hold
  `f3411423` plus the same changes as 15 commits (tip `f0f4ad36`); patch 0016 has no commit there because it
  changes files that Armbian's driver step adds to the tree during the build. The 4.0 kernel is the tag
  `pi-desktop-4.0` in the same repository.

  | Patch | What it does |
  | --- | --- |
  | 0001 drm/rockchip: vop2: reject AFBC modifier | no flicker at 4K@120 (AFBC scanout was the cause) |
  | 0003 drm/rockchip: vop2: raise dclk ceiling to 1200 MHz | 4K@120 pixel clock |
  | 0004 drm/rockchip: vop2: keep the HDMI-PHY-PLL dclk decision at the 600 MHz TMDS limit | FRL modes take dclk from a PLL that can reach them |
  | 0005 arm64: dts: orangepi-5: source vp0 dclk from v0pll | the matching device-tree side (the CMA pool is set on the kernel command line instead: `cma=512M` in `bootenv/rk35xx.txt`) |
  | 0006 net: wireless: bcmdhd: handle NL80211_WPA_VERSION_3 | WPA3/SAE with wpa_supplicant 2.11 (deauth 13 fix) |
  | 0007 drm/rockchip: dw_hdmi_qp: optional cap on the FRL per-lane rate | `rockchipdrm.frl_max_rate_per_lane` knob |
  | 0008 drm/bridge: dw-hdmi-qp: tunable FLT_update poll interval | `dw_hdmi_qp.frl_update_poll_ms` (0 in the image: stops the DDC polling that blanked the screen) |
  | 0009 drm/rockchip: dw_hdmi_qp: hide HDMI 2.1 FRL modes unless allow_frl=1 | 120 Hz is opt-in by boot argument |
  | 0010 phy: rockchip: samsung-hdptx: don't touch FFE registers while suspended | blank/wake hang at 120 Hz |
  | 0011 drm/bridge: dw-hdmi-qp: retrain an FRL link after a short HPD drop | black screen after a monitor power-cycle |
  | 0012 wifi: rtw88: Armbian's upstream-wireless backport, refreshed for 6.1.189 | Armbian's `patch/misc/rtw88/6.1/` driver (Realtek USB/SDIO WiFi, from linux 6.7.4) with the one hunk dropped that stable 6.1.189 already carries; needed because the recipe skips `driver_rtw88` |
  | 0013 rtw88: decrease the log level of tx report | Armbian's companion patch: no "failed to get tx report" dmesg spam |
  | 0014 rtw88: sdio: fix incorrect RF path detection when MAC is powered off | Armbian's companion patch: RTL8822CS detected as 2T2R |
  | 0015 wifi: aic8800: tdls_mgmt takes link_id on 6.1.189 | the vendor aic8800 driver builds again after stable's cfg80211 `tdls_mgmt` change |
  | 0016 wifi: Armbian-added drivers: build on stable 6.1.189 | rtl8192eu, rtl8811cu, rtl8812au, rtl88x2bu and uwe5622 (added by Armbian's driver step) build again after the `usb_driver` and `tdls_mgmt` interface changes in 6.1.188/6.1.189; version guards only |
  | 0017 Bluetooth: hci_h4: rate-limit "Frame reassembly failed" | one UART power-cycle under a live hci device no longer floods the journal (hundreds of thousands of lines) |

  0002 (a device-tree CMA bump) was in 4.0 and is gone: the image sets `cma=512M` on the kernel command line.
  0012–0014 are Armbian's patches, refreshed; 0001, 0003–0011 and 0015–0017 are Plaid Pi's.

- **U-Boot**: Armbian's build of [radxa/u-boot](https://github.com/radxa/u-boot) branch `next-dev-v2024.10`,
  commit `39cd993e5d6296635438e84f4576b3a9bf76f86e` (pinned by the same config hook), with the framework's own
  patch set (`patch/u-boot/legacy/u-boot-radxa-rk35xx*`). Nothing in this recipe changes U-Boot. The RK3588 boot
  path uses Rockchip's binary DDR-init and BL31 blobs (`rkbin`) as every vendor-kernel RK3588 image does.
- **Firmware**: `armbian-firmware` from the framework (the AP6275P WiFi/BT firmware comes from there; the recipe
  appends three Bluetooth coexistence parameters to its NVRAM file). The Mali CSF firmware
  (`mali_csffw.bin`) ships inside the libmali package.

## Notes for whoever rebuilds this

- `PIDESKTOP_VERSION="5.0"` in `config-pidesktop3.conf` is the version string the image shows
  (`/etc/os-release`, MOTD, `/etc/issue`, fastfetch). The board config is still called `pidesktop3` — that is
  the `./compile.sh` argument, not the version — and the internal names (`pidesktop-*` scripts, `pi-desktop`
  paths, the `Pi-Desktop_…` output image name) stay as they were; only the user-visible name changed to Plaid Pi.
  The rebuilt gnome-control-center keeps its `+pd3.4` package revision.
- The framework's `userpatches/` skeleton normally contains dozens of empty directories (`atf/`, `u-boot/*`,
  `kernel/*` for other families). Git does not track empty directories, so they are absent here; the
  framework does not need them.
- `parked/` (unused variants and backups) is not published.
- The fastfetch logo `overlay/pidesktop/fastfetch/plaid.ans` is generated by `plaid_logo.py` next to it.
- Neither Firefox nor Google Chrome is in the image (Mozilla's distribution policy allows unaltered copies
  only, Google's licence forbids redistribution). Both are first-click installers: Chromium (xtradeb PPA) is
  the shipped browser; Firefox is fetched from the Mozilla Team PPA, unmodified, and is started by a launcher
  from `overlay/pidesktop/firefox/` that puts `libpidesktop-ffmali` first on its library path and applies the
  VA-API prefs and a neutral policy (telemetry, studies and Pocket off); Chrome is fetched from Google's signed
  repository. VSCodium replaces VS Code. Ubuntu's wallpapers and docs are removed and the OS name is Plaid Pi
  (Canonical's IP policy for modified images).
- mpv is held (`apt-mark hold`): an Ubuntu update would replace the `+pd1` build and draw 10-bit video dark on
  the Mali driver. gst-plugins-good is not held; a newer Ubuntu security update replaces it and the first-boot
  check reports which build is present.

## Licensing

- The recipe — `customize-image.sh`, the config and hooks, the overlay scripts and units, the kernel patches'
  build glue and the helper scripts in this repository — is **GPL-3.0-or-later** ([LICENSE](LICENSE)).
  The kernel patches themselves are contributions to a GPL-2.0 kernel tree and carry that licence.
  `libpidesktop-ffmali` and the mpv patches are LGPL-2.1-or-later (see [SOURCES.md](SOURCES.md)).
- The Plaid Pi artwork (wallpaper, screensaver video, terminal logo, logo and wordmark, installer icons) is
  **CC BY-SA 4.0** ([ARTWORK.md](ARTWORK.md), [LICENSES/CC-BY-SA-4.0.txt](LICENSES/CC-BY-SA-4.0.txt)).
- Rebuilt and third-party binaries keep their own licences, listed per item in [SOURCES.md](SOURCES.md).
- Ubuntu, Armbian, GNOME, Rockchip, Orange Pi, ARM and Mali are trademarks of their owners. The image is an
  independent build and is not endorsed by any of them.

## About the authors

Plaid Pi is maintained by [defcom5-rockchip](https://github.com/defcom5-rockchip). Much of this recipe,
the overlay scripts and the kernel patches were written together with an LLM assistant (Anthropic's Claude);
the kernel patches say so in their trailers, and the design decisions, testing on hardware and every release
call were the maintainer's. Bugs and questions: <https://github.com/defcom5-rockchip/pi-desktop/issues>.
