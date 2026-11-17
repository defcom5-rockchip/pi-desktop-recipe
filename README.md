# Plaid Pi Plus 6.5 — build recipe

This repository is the complete build recipe for **Plaid Pi Plus 6.5**, the Orange Pi 5 Plus edition of Plaid Pi (formerly Pi-Desktop; 4.5 was built but never
published), a desktop Linux image for the **Orange Pi 5 Plus** (Rockchip RK3588; the 6.5 release image, KDE Plasma 6.6)
and the **Orange Pi 5B** (RK3588S; the 6.0 release image, GNOME 50). It is an
[Armbian build framework](https://github.com/armbian/build) `userpatches/` layer: Ubuntu 26.04 LTS "Resolute" with
GNOME 50 or KDE Plasma 6.6 on the Rockchip vendor 6.1 kernel — Armbian's `rk-6.1-rkr7.2` tree merged with upstream stable
Linux 6.1.191 (kernel version string `6.1.191-vendor-rk35xx`) — plus the Plaid Pi additions:

- the 4K@120 Hz HDMI 2.1 (FRL) kernel work, AFBC flicker fix, WPA3 fix for the AP6275P WiFi, and the fixes that
  keep Armbian's out-of-tree WiFi drivers building on stable 6.1.y, the 6.1.191 follow-ups (Bluetooth MGMT use-after-frees,
  the ext4 buddy-cache NULL dereference, bcmdhd's duplicate cipher suites, the stmmac statistics reset) and the Orange Pi 5
  Plus display clock tree (`userpatches/kernel/rk35xx-vendor-6.1/`, 25 patches),
- GNOME edition: the ARM Mali G610 userspace driver (libmali, wayland-gbm) with a small `EGL_EXT_device_query` shim in the
  libmali hook, and `libpidesktop-ffmali`, a library the Firefox launcher loads so the unmodified Firefox, once the
  user installs it, runs on the GPU and decodes 8- and 10-bit video on the VPU,
- KDE edition (the 6.5 Orange Pi 5 Plus image): KDE Plasma 6.6 on Mesa's open Panthor driver (`PIDESKTOP_GPU_STACK=panthor`)
  with the Plaid look-and-feel, Dolphin's Network Drive and disc menus,
- hardware video decode (H.264, HEVC, VP9, AV1) in Chromium, mpv and the first-click-installed browsers (Rockchip
  MPP with Plaid Pi's AV1, VP9 and film-grain patches, RGA, rockchip-vaapi 4.0.0), and mpv 0.42 rebuilt with the patches
  that draw zero-copy 8- and 10-bit video correctly on the Mali driver, with DVD-Audio and the native PipeWire output,
- Cinemosk, the picture-settings app, with its mpv script and the DVD/Blu-ray folder player
  (`overlay/pidesktop/usr/local/bin/cinemosk*`, `overlay/pidesktop/etc/mpv/scripts/pidesktop-cinema.lua`),
- PipeWire 1.6.10 / WirePlumber 0.5.18 with a hi-res audio lane, real-time scheduling and a working 3.5 mm jack,
  and GStreamer 1.28.9 (its FLAC seek fix included),
- GNOME edition: a screensaver service in place of screen blanking, with a patched GNOME Settings Power panel,
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
| `userpatches/overlay/pidesktop/debs/` | The pre-built `.deb` inputs (`gcc/`, `gstreamer/`, `media/`, `pipewire/`, `pro-updates/`, `rhythmbox/` and the libmali package); fetched by `fetch-inputs.sh`, not in git. |
| `userpatches/kernel/rk35xx-vendor-6.1/` | The 25 kernel patches applied on top of the pinned kernel source. |
| `userpatches/linux-rk35xx-vendor.config` | The kernel config fed to the build (Armbian's `config/kernel/linux-rk35xx-vendor.config` plus `RT_GROUP_SCHED` off and the lockup detector on). Two hooks in the config file adjust it further: `armbian_kernel_config__zz_pidesktop_no_rt_group_sched` keeps the framework from switching `RT_GROUP_SCHED` back on; `armbian_kernel_config__zz_pidesktop_hardening` turns on Yama, hardened usercopy, slab freelist hardening/randomisation and `init_on_alloc`, and builds the Mali kernel driver without its debug options. |
| `userpatches/bootenv/rk35xx.txt` | Boot environment (`cma=512M`, FRL poll off); `customize-image.sh` adds `rockchipdrm.allow_frl=1` to the image's boot arguments. |
| `userpatches/gcc/` | The gnome-control-center patch and the script that rebuilds the `+pd3.4` packages. |
| `userpatches/rhythmbox/` | The Rhythmbox 3.5.1 build script and its one patch. |
| `userpatches/mpv/` | The two mpv patches (`patches/`), the `mpv.conf` the 6.5 mpv packages carry, and the 4.5–6.0 record (`build-mpv-deb.sh`, which turned Ubuntu's `mpv 0.41.0-2ubuntu4` source into `+pd2`). 6.5's mpv 0.42 is built by `userpatches/backports-2026-11/`. |
| `userpatches/gst-plugins-good/` | The 4.5–6.0 record: the upstream flacparse patch and the script that rebuilt Ubuntu's `gst-plugins-good1.0 1.28.2-2ubuntu0.4` as `+pd1`. 6.5 ships GStreamer 1.28.9 from `userpatches/backports-2026-11/` instead. |
| `userpatches/backports-2026-11/` | The script (`run-backports.sh`) and the patched source packages (`sources/*/*.dsc` + `.debian.tar.xz`) that built 6.5's mpv 0.42, libplacebo 7.387, libdvdread 7.1.1 and GStreamer 1.28.9 packages in an arm64 Ubuntu 26.04 chroot; its README lists the per-package changes. |
| `userpatches/staged-experiments/` | Notes and patches from the 4K@120 investigation. Not part of the build (the framework ignores this directory); kept as the record behind kernel patches 0007–0011. |
| `userpatches/INPUTS.sha256` | Checksums of the 63 pre-built inputs, with the path each one belongs at under `userpatches/`. |
| `fetch-inputs.sh` | Downloads the pre-built inputs into place and verifies them. |
| `kernel-config/config-6.1.191-vendor-rk35xx` | `/boot/config-6.1.191-vendor-rk35xx` of the 6.5 release image (the config the shipped kernel was actually built with). `config-6.1.189-vendor-rk35xx` is the 5.0–6.0 kernel's, `config-6.1.172-vendor-rk35xx` the 4.0 kernel's. |
| `manifest/packages-6.5-kde.tsv` | `dpkg-query -W` of the 6.5 release image (Orange Pi 5 Plus, KDE), read from the image file: every package installed in the image, with its version. `packages-6.0.tsv` (5B, GNOME), `packages-6.0-kde.tsv`, `-5.5`, `-5.0` and `-4.0` are the earlier lists. |
| `manifest/apt-sources-6.5-kde.txt` | `apt-cache policy` over the 6.5 release image's own sources, pins and package lists, as built: the archives and pins the image updates from (the earlier releases' lists sit next to it). |
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
   (cd pi-desktop-recipe && ./fetch-inputs.sh)    # downloads about 107 MB into pi-desktop-recipe/userpatches/…
   cp -r pi-desktop-recipe/userpatches .          # …so copy again, or run fetch-inputs.sh with the copy
   ```

   `fetch-inputs.sh` only writes files listed in `userpatches/INPUTS.sha256`, each verified by SHA-256 before
   it is moved into place. Simplest is to clone this repository, run `./fetch-inputs.sh` inside it, and then
   copy `userpatches/` into the framework checkout once.

3. Build, exactly as the header of `userpatches/config-pidesktop3.conf` says:

   ```sh
   # the 6.5 release image: Orange Pi 5 Plus, KDE edition
   sudo env PREFER_DOCKER=no PIDESKTOP_BOARD=orangepi5-plus ./compile.sh PIDESKTOP_BOARD=orangepi5-plus PIDESKTOP_DESKTOP=kde pidesktop3
   # the Orange Pi 5B GNOME image (6.0's form)
   sudo env PREFER_DOCKER=no ./compile.sh pidesktop3
   ```

   The framework downloads the kernel and U-Boot sources, applies the patches, builds the kernel, U-Boot and
   the BSP packages, debootstraps the Ubuntu root filesystem, installs the desktop (GNOME, or KDE Plasma with
   `PIDESKTOP_DESKTOP=kde`), and finally runs
   `customize-image.sh` inside the image. A first build takes a few hours; later builds reuse the cache.

   The kernel source is pinned by the `post_family_config__pidesktop_pinned_sources` hook in the config:
   `KERNELSOURCE` is <https://github.com/defcom5-rockchip/linux-rockchip.git> at commit
   `ea135f2edfaf9e1c29c47e88e2d9fa4f8404fda5` (`KERNELBRANCH=commit:…`, tag `pi-desktop-6.5`), and U-Boot is pinned likewise. The stock
   framework takes that https URL as it is; `PIDESKTOP_KERNELSOURCE=file:///path/to/clone` works only with a small
   local change to the framework's `lib/functions/general/git-ref2info.sh` (the config comment says so). The
   same hook skips Armbian's `driver_rtw88` step, because its rtw88 backport no longer applies to the stable 6.1.y merge;
   kernel patch 0012 carries it refreshed.

4. The image lands in `output/images/`:

   ```
   output/images/Pi-Desktop_26.11.0-trunk_Orangepi5-plus_resolute_vendor_6.1.191_kde-plasma_desktop.img
   output/images/Pi-Desktop_26.11.0-trunk_Orangepi5-plus_resolute_vendor_6.1.191_kde-plasma_desktop.img.sha
   output/images/Pi-Desktop_26.11.0-trunk_Orangepi5-plus_resolute_vendor_6.1.191_kde-plasma_desktop.img.txt
   (a 5B GNOME build is named …_Orangepi5b_resolute_vendor_6.1.191_gnome_desktop.img)
   ```

   (`COMPRESS_OUTPUTIMAGE=sha,img` leaves a raw image plus checksum; the published `.img.zst` is that file
   compressed with `zstd -19`.) The published 6.5 image is `Plaid-Pi-Plus-6.5-orangepi5-plus.img.zst`, 1,590,814,467 bytes,
   SHA-256 `2b73c85faa0cc0dc63372f404eda59ab2378347b04377b30f575664a501bd61f` (6.0: `Plaid-Pi-6.0-orangepi5b.img.zst`, 1,496,576,700 bytes,
   `a851c7108c0618765c791a7b1ec0690178bbaf13f49c7fbea95692fd25ed3f16`). `customize-image.sh` also writes
   `/etc/pi-desktop-manifest.txt` into the image with the key package versions and holds, and prints it in the
   build log.

Build-time switches live in `config-pidesktop3.conf`: `PIDESKTOP_VERSION` is the string shown in
`/etc/os-release`, the MOTD and `/etc/issue`; `PIDESKTOP_BOARD=orangepi5-plus|orangepi5b|orangepi5` selects the board
and `PIDESKTOP_DESKTOP=kde|gnome` the edition (the 6.5 release image is the 5 Plus KDE build; the 5B and 5 default to
GNOME); `PIDESKTOP_GPU_STACK=panthor|mali|mesa` picks the GPU stack (KDE defaults to Panthor, GNOME to libmali;
`mesa` is a llvmpipe control image).

## Build inputs

63 pre-built files are not in git (`.gitignore` keeps them out): 60 `.deb` packages under
`userpatches/overlay/pidesktop/debs/`, the patched `libmali-hook.so.1.9.0` under `overlay/pidesktop/gpu/`,
`libpidesktop-ffmali.so.1` under `overlay/pidesktop/firefox/ffmali/`, and the screensaver video under
`overlay/pidesktop/usr/share/pi-desktop/screensaver/`; about 107 MB together. They are published as the GitHub
release **`inputs-6.5`** of this repository, and `fetch-inputs.sh` fetches them into place (GitHub stores release
assets with `~` in the name replaced by `.`, so the script requests `pipewire_1.6.10-1.pd55_arm64.deb` and saves it
under its real name). `userpatches/INPUTS.sha256` is in `sha256sum` format, so
`cd userpatches && sha256sum -c INPUTS.sha256` also verifies a populated tree.

What each input is, where it was built from and under which licence is in [SOURCES.md](SOURCES.md). The
packages we rebuilt or built (gnome-control-center, Rhythmbox, PipeWire, WirePlumber, MPP, rockchip-vaapi, mpv,
libplacebo, libdvdread, GStreamer, Pro Updates, libpidesktop-ffmali) are reproducible from the sources named there; the libmali
package is ARM's proprietary driver as packaged by Rockchip and is not built from source.

## Kernel, U-Boot and firmware

- **Kernel**: <https://github.com/defcom5-rockchip/linux-rockchip> at commit
  `ea135f2edfaf9e1c29c47e88e2d9fa4f8404fda5`, tag **`pi-desktop-6.5`**. That is [armbian/linux-rockchip](https://github.com/armbian/linux-rockchip)
  branch `rk-6.1-rkr7.2` at `44bbd021d7808cab93d1f2d64c1f092038257576` (Linux 6.1.172, Rockchip BSP release
  rkr7.2) merged with upstream stable `v6.1.189` (merge commit `7b6195db`, plus "Adapt vendor drivers to interface
  changes in stable 6.1.189", `f3411423`, the 5.0–6.0 kernel, tag `pi-desktop-5.0`), then merged with upstream stable
  `v6.1.191` (merge commit `adcf1751`) plus one commit, "Adapt vendor drivers to interface changes in stable 6.1.191"
  (`ea135f2`). On top of it the framework applies Armbian's own vendor-kernel patch set
  (`patch/kernel/rk35xx-vendor-6.1/`) and its driver step, then the 25 patches in
  `userpatches/kernel/rk35xx-vendor-6.1/`, with `userpatches/linux-rk35xx-vendor.config` and the hooks named
  above (the resulting `/boot/config` is in `kernel-config/`). The tag `pi-desktop-6.5` is the bare base the framework
  patches: the 25 patches live only in `userpatches/kernel/` (the 5.0 tag carried its patches as commits too, all but 0016,
  which changes files that Armbian's driver step adds to the tree during the build). The 4.0 kernel is the tag
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
  | 0020 arm64: dts: orangepi-5-plus: source vp0 dclk from v0pll | the Orange Pi 5 Plus counterpart of 0005: 4K@120 pixel clock on the 5 Plus |
  | 0021 bcmdhd: list each BIP_GMAC cipher suite once | stable 6.1.191 rejects a wiphy with duplicate cipher suites; without this the AP6275P driver fails to register and the board has no Wi-Fi (sent to Armbian: linux-rockchip #620) |
  | 0022 net: stmmac: don't clear the network statistics in .ndo_open | 6.1.191's per-cpu statistics: the vendor driver's memset cleared live counters (the Orange Pi 5B's wired port) |
  | 0023–0025 Bluetooth: MGMT: fix possible use-after-frees, the set_mesh crash and the command-list corruption | upstream fixes (Luiz Augusto von Dentz) backported to this tree |
  | 0026 drm/rockchip: dw_hdmi_qp: honour the standard "max bpc" property for HDR output; vop2: `hdr_passthrough` module parameter | both inert by default; for colour-managed compositors (the KWin HDR experiments) |
  | 0027 ext4: mballoc: handle NULL from `__filemap_get_folio()` on 6.1.y | 6.1.191's mballoc folio backport tests `IS_ERR()` where 6.1.y still returns NULL: without this a buddy-bitmap cache miss (any allocation after memory pressure) is a kernel NULL dereference |
  | 0028 Revert "net: mac80211: Added p2p0 for ap mode in softmac" | Rockchip's mac80211 added a second station netdev ("p2p%d") on every P2P-capable card; on the 5 Plus's AX210 both got the same udev name, only one could be up, and a saved network stopped reconnecting when the name moved (sent to Armbian: linux-rockchip #621) |

  0002 (a device-tree CMA bump) was in 4.0 and is gone: the image sets `cma=512M` on the kernel command line.
  0012–0014 are Armbian's patches, refreshed; 0023–0025 are upstream fixes; 0001, 0003–0011, 0015–0017, 0020–0022,
  0026–0028 are Plaid Pi's (0028 reverts a Rockchip BSP commit). 0018 and 0019 were never used.

- **U-Boot**: Armbian's build of [radxa/u-boot](https://github.com/radxa/u-boot) branch `next-dev-v2024.10`,
  commit `39cd993e5d6296635438e84f4576b3a9bf76f86e` (pinned by the same config hook), with the framework's own
  patch set (`patch/u-boot/legacy/u-boot-radxa-rk35xx*`). Nothing in this recipe changes U-Boot. The RK3588 boot
  path uses Rockchip's binary DDR-init and BL31 blobs (`rkbin`) as every vendor-kernel RK3588 image does.
- **Firmware**: `armbian-firmware` from the framework (the AP6275P WiFi/BT firmware comes from there; the recipe
  appends three Bluetooth coexistence parameters to its NVRAM file, and restores the lowercase `nvram_ap6275p.txt`
  link the driver loads when the firmware package ships it as a plain text file, as the November 2026 package does). The Mali CSF
  firmware (`mali_csffw.bin`, used by Panthor on the KDE image) comes from `armbian-firmware` as well.

## Notes for whoever rebuilds this

- `PIDESKTOP_VERSION="6.5"` in `config-pidesktop3.conf` is the version string the image shows
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
  the shipped browser on the GNOME image (the KDE image installs it on first click, like the others); Firefox is fetched from the Mozilla Team PPA, unmodified, and is started by a launcher
  from `overlay/pidesktop/firefox/` that puts `libpidesktop-ffmali` first on its library path and applies the
  VA-API prefs and a neutral policy (telemetry, studies and Pocket off); Chrome is fetched from Google's signed
  repository. VSCodium replaces VS Code. Ubuntu's wallpapers and docs are removed and the OS name is Plaid Pi
  (Canonical's IP policy for modified images).
- mpv and libmpv2 are held (`apt-mark hold`): a future Ubuntu mpv 0.42 or newer would replace the `~pd4` build and draw 10-bit video dark
  on the Mali driver. The GStreamer 1.28.9 packages are not held: `~pd1` sorts below any Ubuntu update of the same
  upstream version, and the first-boot check reports which build is present.

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
