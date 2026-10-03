# Sources and licences

Where every component that Pi-Desktop 4.0 "Plaid" rebuilds or ships as a pre-built binary comes from, and
under which licence. Versions are the `Version` fields of the packages (`dpkg-deb -f <deb> Version`) and
match `manifest/packages-4.0.tsv`, the package list of the release test board.

Three kinds of components appear in the image:

1. **This repository** — the recipe, scripts, units and patches. GPL-3.0-or-later (`LICENSE`); artwork
   CC BY-SA 4.0 (`ARTWORK.md`).
2. **Pre-built inputs** — the 30 files in `userpatches/INPUTS.sha256`, attached to the `inputs-4.0`
   release. Each is listed below with its origin and licence.
3. **Archive packages** — everything else is installed at build time from Ubuntu's archive
   (`ports.ubuntu.com`, resolute + updates + security), two Launchpad PPAs (`xtradeb/apps` for Chromium,
   `mozillateam/ppa` for Firefox) and Armbian's own BSP/kernel/U-Boot packages built by the framework.
   `manifest/packages-4.0.tsv` has every package and version; `manifest/apt-sources-4.0.txt` has the
   archives and pins the image updates from. Their sources are the respective archives' source packages.

## Pre-built inputs

Paths are under `userpatches/overlay/pidesktop/`.

### Packages we rebuilt from source

| Input | Version | Built from | Licence |
| --- | --- | --- | --- |
| `debs/gcc/gnome-control-center_*_arm64.deb`, `gnome-control-center-data_*_all.deb`, `gnome-control-center-faces_*_all.deb` | `1:50.3-0ubuntu0.2+pd3.3` | Ubuntu resolute source package `gnome-control-center 1:50.3-0ubuntu0.2` plus `userpatches/gcc/pidesktop-power-screensaver.patch` (Power panel: a Screensaver group replaces Automatic Screen Blank), built in a resolute chroot by `userpatches/gcc/rebuild-settings.sh`. | GPL-2.0-or-later (parts Expat, CC0-1.0, per Debian copyright) |
| `debs/rhythmbox/rhythmbox_3.5.1-1~pd3_arm64.deb` | `3.5.1-1~pd3` | GNOME release tarball `rhythmbox-3.5.1.tar.xz` from download.gnome.org (SHA-256 checked by the script) plus `userpatches/rhythmbox/patches/0001-prefer-dark-theme.patch`, every optional feature enabled, packaged as one .deb by `userpatches/rhythmbox/build-rhythmbox-deb.sh`. `userpatches/rhythmbox/SHA256SUMS` records the hashes of script, patch and resulting .deb. | GPL-2.0-or-later with the GStreamer plugin exception (upstream `COPYING`) |
| `debs/pipewire/pipewire_*`, `pipewire-bin`, `pipewire-pulse`, `pipewire-alsa`, `pipewire-jack`, `pipewire-audio`, `pipewire-audio-client-libraries`, `libpipewire-0.3-0t64`, `libpipewire-0.3-common`, `libpipewire-0.3-modules`, `libpipewire-0.3-modules-x11`, `libspa-0.2-modules`, `libspa-0.2-bluetooth`, `libspa-0.2-jack`, `libspa-0.2-libcamera`, `gstreamer1.0-pipewire` | `1.6.9-2~pd31` | Debian unstable source package `pipewire 1.6.9-2` (Utopia Maintenance Team; includes the CVE-2026-14330 fix), rebuilt without source changes for Ubuntu resolute arm64; the only change is the `~pd31` changelog entry. Source: `https://deb.debian.org/debian/pool/main/p/pipewire/pipewire_1.6.9-2.dsc` / <https://salsa.debian.org/utopia-team/pipewire>. | MIT (Expat); some modules LGPL-2.1+/BSD per Debian copyright |
| `debs/pipewire/wireplumber_*`, `libwireplumber-0.5-0_*` | `0.5.17-1~pd31` | Debian unstable source package `wireplumber 0.5.17-1`, rebuilt without source changes for resolute arm64 (`~pd31` changelog entry only). Source: `https://deb.debian.org/debian/pool/main/w/wireplumber/wireplumber_0.5.17-1.dsc` / <https://salsa.debian.org/utopia-team/wireplumber>. | MIT (Expat) |
| `debs/media/librockchip-mpp1_*`, `librockchip-mpp-dev_*`, `librockchip-vpu1_*` | `1.5.0+git20260805.a8b19653+ds-0ubuntu1~rk1+pd31` | Rockchip Media Process Platform, upstream <https://github.com/rockchip-linux/mpp>, git `a8b19653` (2026-08-05) via the `~rk1` Ubuntu packaging maintained by Yi Ding (changelog entries from the ysp fork: VP9 show-existing fixes, vepu580 HEVC register fix), rebuilt by defcom5-rockchip for resolute against the vendor 6.1 rkr7.2 kernel (`+pd31` changelog entry: rebuild only). The `~rk1+pd31` source package (`.dsc` with its `debian/` directory) is not in this repository — see *Gaps* below. | Apache-2.0 |
| `debs/media/rockchip-vaapi_2.2.0-1~pd3_arm64.deb` | `2.2.0-1~pd3` | VA-API driver on top of MPP: <https://github.com/defcom5-rockchip/rockchip-vaapi> release 2.2.0 (a fork of Eduardo García-Mádico Portabella's `rockchip-vaapi`; copyright both), built for resolute against the MPP package above. | LGPL-2.1-or-later |

### Pre-built, not rebuilt here

| Input | Version | Origin | Licence |
| --- | --- | --- | --- |
| `debs/media/librga2_*_arm64.deb` | `2.2.0+git20260725.26a50ef-0ubuntu1~rk1` | Rockchip RGA 2D engine library, upstream <https://github.com/rockchip-linux/linux-rga> (`librga-fork` git `26a50ef`), the `~rk1` Ubuntu packaging maintained by Yi Ding. Used as built by that packaging; no Pi-Desktop change (no `pd` suffix). | Apache-2.0 (bundled libdrm headers Expat; `debian/*` GPL-3+) |
| `debs/libmali-valhall-g610-g24p0-wayland-gbm_1.9-1_arm64.deb` | `1.9-1` | ARM Mali G610 (Valhall) userspace driver, release g24p0, Wayland + GBM variant, as packaged by Rockchip (`libmali` Debian packaging by Jeffy Chen, package maintainer Rockchip; `Homepage: https://github.com/rockchip-linux/libmali`, mirrored as the `libmali` branch of <https://github.com/JeffyCN/mirrors>). Contains the proprietary driver libraries (`libmali.so`, EGL/GLES/OpenCL/Vulkan/GBM front-ends), the Mali CSF firmware `mali_csffw.bin`, and the GPL `libmali-hook`. The recipe pins the package with `apt-mark hold`. | Driver and firmware: **ARM End User Licence Agreement** (proprietary; the EULA text is in the package's `copyright` file, `LES-PRE-20769`). `hook/`, `meson`, scripts: GPL-2.0-or-later. |
| `gpu/libmali-hook.so.1.9.0` | sha256 `6ae43aa0…` | The `libmali-hook` shared library from the libmali source tree above (GPL-2.0-or-later, Jeffy Chen), rebuilt with `userpatches/overlay/pidesktop/gpu/0001-libmali-hook-EGL_EXT_device_query-shim-for-Firefox-gfxtest.patch` (a minimal `EGL_EXT_device_query` shim so Firefox's graphics probe accepts the blob). `customize-image.sh` diverts the package's copy and installs this one in its place. The patch is the complete Pi-Desktop change; the hook's own source is `hook/` in the libmali repository. | GPL-2.0-or-later |
| `usr/share/pi-desktop/screensaver/plaid-penguin-drop.mp4` | 60 s, 3840×2160, H.264 30 fps | Pi-Desktop screensaver video (penguins under plaid parachutes), original artwork by defcom5-rockchip; see `ARTWORK.md`. | CC BY-SA 4.0 |

## Components outside the inputs that carry non-free terms

| Component | Where it comes from | Licence |
| --- | --- | --- |
| Rockchip boot blobs (DDR init, BL31/`rkbin`) | Pulled by the Armbian framework for the `spl-blobs` boot scenario of the RK3588 U-Boot build. Not in this repository. | Rockchip binary licence (redistributable blobs, as in every RK3588 vendor image) |
| AP6275P WiFi/Bluetooth firmware and NVRAM | `armbian-firmware` (Armbian's firmware package). `customize-image.sh` diverts `nvram_AP6275P.txt` and appends three `btc_params` coexistence lines. | Vendor firmware terms (linux-firmware-style redistribution) |
| Chromium (`xtradeb/apps` PPA) | Installed from the PPA at build time, pinned above Ubuntu's; `etc/chromium.d/pidesktop-vaapi` adds the VA-API flags. | BSD-3-Clause |
| Firefox (`mozillateam/ppa` PPA) | **Not in the image** (Mozilla's distribution policy covers unaltered copies only). The "Firefox" launcher runs `pidesktop-get firefox`, which installs the Mozilla Team build from the PPA on the user's machine and then applies the pieces staged from `overlay/pidesktop/firefox/` (Mali libGL wrapper, VA-API prefs, neutral policy). | MPL-2.0 |
| Google Chrome | **Not in the image.** The "Google Chrome" launcher runs `pidesktop-chrome`, which offers to download Chrome from Google's signed repository on the user's own machine (Google's terms forbid redistribution). | Google Chrome Terms of Service (user-accepted at download) |
| Ubuntu base, GNOME, Armbian BSP | Ubuntu archive / built by the framework. Pi-Desktop renames the product in `/etc/os-release`, the MOTD and `/etc/issue`, removes Armbian's `armbian-config`, `armbian-zsh` and Plymouth theme, and keeps the Armbian BSP (boot scripts, first-login). | Per package; Ubuntu and Armbian trademark policies apply to the names and logos |

## Gaps the maintainer should close before publishing

- **MPP `~rk1+pd31` source package**: the rebuilt MPP packages are Apache-2.0 (no source obligation), but the
  `debian/` packaging used for the `+pd31` rebuild is not in this repository. Add the `.dsc`/`.debian.tar.xz`
  to the `inputs-4.0` release or a note on where the `~rk1` packaging lives. Note also that the image's
  `/usr/share/doc/pi-desktop/copyright` (in `overlay/pidesktop/usr/share/doc/pi-desktop/`) describes this
  package as "librockchip-mpp (10-bit fix)", while the package changelog for `+pd31` says "rebuild for
  resolute" only; if a 10-bit patch is in the build, it belongs in this repository (or the `inputs-4.0`
  release) and in the changelog.
- **librga2**: the `~rk1` binary was taken as built; record the PPA/build it was downloaded from.
- **libmali hook**: the libmali git commit the hook was built from is not recorded; the patch applies to the
  `hook/` sources of the 1.9 packaging. Record the commit (or attach the exact `hook.c` used) so the GPL
  "complete corresponding source" for `libmali-hook.so.1.9.0` is unambiguous.
- **libmali redistribution**: ARM's EULA governs the driver libraries and firmware. Rockchip and several
  distributions ship this package, but confirm that the EULA's redistribution terms are acceptable for a public
  image before the release goes out, or move the libmali .deb to a download-on-first-boot step.
- **Screensaver video generator**: the script that renders `plaid-penguin-drop.mp4` is not in this
  repository; CC BY-SA asks only for attribution and share-alike of the work itself, but publishing the
  generator would make the artwork reproducible.
