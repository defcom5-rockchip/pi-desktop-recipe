# Pi-Desktop 4.0 "Plaid" — build recipe

This repository is the complete build recipe for **Pi-Desktop 4.0 "Plaid"**, a desktop Linux image for the
**Orange Pi 5B** (Rockchip RK3588S). It is an [Armbian build framework](https://github.com/armbian/build)
`userpatches/` layer: Ubuntu 26.04 LTS "Resolute" with GNOME 50 on the Rockchip vendor 6.1.172 kernel
(release rkr7.2) plus the Pi-Desktop additions:

- the 4K@120 Hz HDMI 2.1 (FRL) kernel work, AFBC flicker fix, WPA3 fix for the AP6275P WiFi
  (`userpatches/kernel/rk35xx-vendor-6.1/`, 11 patches),
- the ARM Mali G610 userspace driver (libmali, wayland-gbm) with a small EGL shim so Firefox, once the user
  installs it, runs on the GPU,
- hardware video decode in Chromium, mpv and the first-click-installed browsers (Rockchip MPP, RGA, rockchip-vaapi),
- PipeWire 1.6.9 / WirePlumber 0.5.17 with a hi-res audio lane, real-time scheduling and a working 3.5 mm jack,
- a screensaver service in place of screen blanking, with a patched GNOME Settings Power panel,
- the Plaid look (wallpaper, terminal palette, fastfetch logo), first-click installers for large apps,
  Bluetooth boot-race fixes, persistent journal, and a few dozen smaller things, all documented inline
  in `userpatches/customize-image.sh`.

Everything that goes into the image either is in this repository, is fetched from a public package archive
at build time, or is a pre-built input attached to a GitHub release of this repository (see
[Build inputs](#build-inputs) and [SOURCES.md](SOURCES.md)).

## Repository layout

| Path | What it is |
| --- | --- |
| `userpatches/` | The Armbian `userpatches/` directory, as used for the release build. Copy it into an Armbian build checkout as-is. |
| `userpatches/config-pidesktop3.conf` | Board/branch/release selection plus the framework hooks (kernel-config hook, base-files pin, armbian-config removal, version hand-over). |
| `userpatches/customize-image.sh` | The Pi-Desktop layer: runs as root inside the image chroot at the end of Armbian's customize step. Every step logs `I: [pi-desktop]` / `W: [pi-desktop]`. |
| `userpatches/overlay/pidesktop/` | Files installed into the image by `customize-image.sh` (bind-mounted at `/tmp/overlay` during the build). |
| `userpatches/overlay/pidesktop/branding/` | The Pi-Desktop logo (SVG, PNG renders, Plymouth images) and the script that generates it. |
| `userpatches/kernel/rk35xx-vendor-6.1/` | The 11 kernel patches applied on top of Armbian's vendor kernel source. |
| `userpatches/linux-rk35xx-vendor.config` | The kernel config fed to the build (Armbian's `config/kernel/linux-rk35xx-vendor.config` plus `RT_GROUP_SCHED` off and the lockup detector on). The `armbian_kernel_config__zz_pidesktop_no_rt_group_sched` hook in the config file keeps the framework from switching `RT_GROUP_SCHED` back on. |
| `userpatches/bootenv/rk35xx.txt` | Boot environment (`cma=512M`, FRL poll off, `allow_frl=1`). |
| `userpatches/gcc/` | The gnome-control-center patch and the script that rebuilds the `+pd3.3` packages. |
| `userpatches/rhythmbox/` | The Rhythmbox 3.5.1 build script and its one patch. |
| `userpatches/staged-experiments/` | Notes and patches from the 4K@120 investigation. Not part of the build (the framework ignores this directory); kept as the record behind kernel patches 0007–0011. |
| `userpatches/INPUTS.sha256` | Checksums of the pre-built inputs, with the path each one belongs at under `userpatches/`. |
| `fetch-inputs.sh` | Downloads the pre-built inputs into place and verifies them. |
| `kernel-config/config-6.1.172-vendor-rk35xx` | `/boot/config-6.1.172-vendor-rk35xx` read from the release test board (the config the shipped kernel was actually built with). |
| `manifest/packages-4.0.tsv` | `dpkg-query -W` of the release test board: every package and version in the image. |
| `manifest/apt-sources-4.0.txt` | `apt-cache policy` of the release test board: the archives and pins the image updates from. |
| `SOURCES.md` | Where every rebuilt or binary component comes from and under which licence. |
| `ARTWORK.md` | The Pi-Desktop artwork and its licence (CC BY-SA 4.0). |
| `LICENSE`, `LICENSES/` | GPL-3.0 (the recipe) and CC BY-SA 4.0 (the artwork) texts. |

`config-example.conf` and `customize-image.sh.armbian-example` are the framework's own templates and are not used.

## How to build

The image was built natively (not in Docker) on an x86-64 host running Ubuntu 26.04, with the Armbian build
framework at the commit below. Other framework revisions may need adjustments: the recipe hooks into framework
internals (`armbian_kernel_config` option arrays, `apt_find_upstream_package_version_and_download_url`,
`chroot_sdcard`) that change over time.

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
   (cd pi-desktop-recipe && ./fetch-inputs.sh)    # downloads ~86 MB into pi-desktop-recipe/userpatches/…
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

4. The image lands in `output/images/`:

   ```
   output/images/Pi-Desktop_26.11.0-trunk_Orangepi5b_resolute_vendor_6.1.172_gnome_desktop.img
   output/images/Pi-Desktop_26.11.0-trunk_Orangepi5b_resolute_vendor_6.1.172_gnome_desktop.img.sha
   output/images/Pi-Desktop_26.11.0-trunk_Orangepi5b_resolute_vendor_6.1.172_gnome_desktop.img.txt
   ```

   (`COMPRESS_OUTPUTIMAGE=sha,img` leaves a raw image plus checksum; the published `.img.zst` is that file
   compressed with `zstd -19`.) `customize-image.sh` also writes `/etc/pi-desktop-manifest.txt` into the
   image with the key package versions and holds, and prints it in the build log.

Build-time switches live in `config-pidesktop3.conf`: `PIDESKTOP_VERSION` is the string shown in
`/etc/os-release`, the MOTD and `/etc/issue`; `PIDESKTOP_GPU_STACK=mesa` builds a control image on stock Mesa
(llvmpipe on this kernel) instead of libmali.

## Build inputs

Thirty pre-built files are not in git (`.gitignore` keeps them out): 29 `.deb` packages under
`userpatches/overlay/pidesktop/debs/`, the patched `libmali-hook.so.1.9.0` under `overlay/pidesktop/gpu/`,
and the screensaver video under `overlay/pidesktop/usr/share/pi-desktop/screensaver/`. They are published as
the GitHub release **`inputs-4.0`** of this repository, and `fetch-inputs.sh` fetches them into place.
`userpatches/INPUTS.sha256` is in `sha256sum` format, so `cd userpatches && sha256sum -c INPUTS.sha256` also
verifies a populated tree.

What each input is, where it was built from and under which licence is in [SOURCES.md](SOURCES.md). The
packages we rebuilt (gnome-control-center, Rhythmbox, PipeWire, WirePlumber, MPP, rockchip-vaapi) are
reproducible from the sources named there; the libmali package is ARM's proprietary driver as packaged by
Rockchip and is not built from source.

## Kernel, U-Boot and firmware

- **Kernel**: [armbian/linux-rockchip](https://github.com/armbian/linux-rockchip) branch `rk-6.1-rkr7.2`,
  commit `44bbd021d7808cab93d1f2d64c1f092038257576` (Linux 6.1.172, Rockchip BSP release rkr7.2), plus the
  11 patches in `userpatches/kernel/rk35xx-vendor-6.1/`, built with `userpatches/linux-rk35xx-vendor.config`
  (the resulting `/boot/config` is in `kernel-config/`). The patched tree is also published as the tag
  **`pi-desktop-4.0`** in <https://github.com/defcom5-rockchip/linux-rockchip>. Armbian's own vendor-kernel
  patch set (`patch/kernel/rk35xx-vendor-6.1/` in the framework) is applied before ours.

  | Patch | What it does |
  | --- | --- |
  | 0001 drm/rockchip: vop2: reject AFBC modifier | no flicker at 4K@120 (AFBC scanout was the cause) |
  | 0002 arm64: dts: orangepi-5: bump CMA pool | CMA for 4K video decode |
  | 0003 drm/rockchip: vop2: raise dclk ceiling to 1200 MHz | 4K@120 pixel clock |
  | 0004 drm/rockchip: vop2: keep the HDMI-PHY-PLL dclk decision at the 600 MHz TMDS limit | FRL modes take dclk from a PLL that can reach them |
  | 0005 arm64: dts: orangepi-5: source vp0 dclk from v0pll; CMA 512M | the matching device-tree side |
  | 0006 net: wireless: bcmdhd: handle NL80211_WPA_VERSION_3 | WPA3/SAE with wpa_supplicant 2.11 (deauth 13 fix) |
  | 0007 drm/rockchip: dw_hdmi_qp: optional cap on the FRL per-lane rate | `rockchipdrm.frl_max_rate_per_lane` knob |
  | 0008 drm/bridge: dw-hdmi-qp: tunable FLT_update poll interval | `dw_hdmi_qp.frl_update_poll_ms` (0 in the image: stops the DDC polling that blanked the screen) |
  | 0009 drm/rockchip: dw_hdmi_qp: hide HDMI 2.1 FRL modes unless allow_frl=1 | 120 Hz is opt-in by boot argument |
  | 0010 phy: rockchip: samsung-hdptx: don't touch FFE registers while suspended | blank/wake hang at 120 Hz |
  | 0011 drm/bridge: dw-hdmi-qp: retrain an FRL link after a short HPD drop | black screen after a monitor power-cycle |

- **U-Boot**: Armbian's build of [radxa/u-boot](https://github.com/radxa/u-boot) branch `next-dev-v2024.10`,
  commit `39cd993e5d6296635438e84f4576b3a9bf76f86e`, with the framework's own patch set
  (`patch/u-boot/legacy/u-boot-radxa-rk35xx*`). Nothing in this recipe changes U-Boot. The RK3588 boot path
  uses Rockchip's binary DDR-init and BL31 blobs (`rkbin`) as every vendor-kernel RK3588 image does.
- **Firmware**: `armbian-firmware` from the framework (the AP6275P WiFi/BT firmware comes from there; the recipe
  appends three Bluetooth coexistence parameters to its NVRAM file). The Mali CSF firmware
  (`mali_csffw.bin`) ships inside the libmali package.

## Notes for whoever rebuilds this

- `PIDESKTOP_VERSION="4.0 Plaid"` in `config-pidesktop3.conf` is the version string the image shows
  (`/etc/os-release`, MOTD, `/etc/issue`, fastfetch). The board config is still called `pidesktop3` — that is
  the `./compile.sh` argument, not the version. The rebuilt gnome-control-center keeps its `+pd3.3` package
  revision.
- The framework's `userpatches/` skeleton normally contains dozens of empty directories (`atf/`, `u-boot/*`,
  `kernel/*` for other families). Git does not track empty directories, so they are absent here; the
  framework does not need them.
- `parked/` (an unused x11 variant of the libmali package) was not carried over.
- The fastfetch logo `overlay/pidesktop/fastfetch/plaid.ans` is referenced as regenerable with a
  `plaid_logo.py`; that generator is not in this repository.
- Neither Firefox nor Google Chrome is in the image (Mozilla's distribution policy allows unaltered copies
  only, Google's licence forbids redistribution). Both are first-click installers: Chromium (xtradeb PPA) is
  the shipped browser; Firefox is fetched from the Mozilla Team PPA and then gets the Mali libGL wrapper,
  VA-API prefs and a neutral policy (telemetry, studies and Pocket off) from `overlay/pidesktop/firefox/`;
  Chrome is fetched from Google's signed repository. VSCodium replaces VS Code. Ubuntu's wallpapers and docs
  are removed and the OS name is Pi-Desktop (Canonical's IP policy for modified images).

## Licensing

- The recipe — `customize-image.sh`, the config and hooks, the overlay scripts and units, the kernel patches'
  build glue and the helper scripts in this repository — is **GPL-3.0-or-later** ([LICENSE](LICENSE)).
  The kernel patches themselves are contributions to a GPL-2.0 kernel tree and carry that licence.
- The Pi-Desktop artwork (wallpaper, screensaver video, terminal logo, installer icons) is
  **CC BY-SA 4.0** ([ARTWORK.md](ARTWORK.md), [LICENSES/CC-BY-SA-4.0.txt](LICENSES/CC-BY-SA-4.0.txt)).
- Rebuilt and third-party binaries keep their own licences, listed per item in [SOURCES.md](SOURCES.md).
- Ubuntu, Armbian, GNOME, Rockchip, Orange Pi, ARM and Mali are trademarks of their owners. The image is an
  independent build and is not endorsed by any of them.

## About the authors

Pi-Desktop is maintained by [defcom5-rockchip](https://github.com/defcom5-rockchip). Much of this recipe,
the overlay scripts and the kernel patches were written together with an LLM assistant (Anthropic's Claude);
the kernel patches say so in their trailers, and the design decisions, testing on hardware and every release
call were the maintainer's. Bugs and questions: <https://github.com/defcom5-rockchip/pi-desktop/issues>.
