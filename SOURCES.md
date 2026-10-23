# Sources and licences

Where every component that Plaid Pi 5.5 rebuilds or ships as a pre-built binary comes from, and
under which licence. Versions are the `Version` fields of the packages (`dpkg-deb -f <deb> Version`) and
match `manifest/packages-5.5.tsv`, the package list of the release test board.

Three kinds of components appear in the image:

1. **This repository** — the recipe, scripts, units and patches. GPL-3.0-or-later (`LICENSE`); artwork
   CC BY-SA 4.0 (`ARTWORK.md`).
2. **Pre-built inputs** — the 36 files in `userpatches/INPUTS.sha256`, attached to the `inputs-5.5`
   release. Each is listed below with its origin and licence.
3. **Archive packages** — everything else is installed at build time from Ubuntu's archive
   (`ports.ubuntu.com`, resolute + updates + security), two Launchpad PPAs (`xtradeb/apps` for Chromium,
   `mozillateam/ppa` for Firefox) and Armbian's own BSP/kernel/U-Boot packages built by the framework.
   `manifest/packages-5.5.tsv` has every package and version; `manifest/apt-sources-5.5.txt` has the
   archives and pins the image updates from. Their sources are the respective archives' source packages.

## Pre-built inputs

Paths are under `userpatches/overlay/pidesktop/`.

### Packages and libraries we built from source

| Input | Version | Built from | Licence |
| --- | --- | --- | --- |
| `debs/gcc/gnome-control-center_*_arm64.deb`, `gnome-control-center-data_*_all.deb`, `gnome-control-center-faces_*_all.deb` | `1:50.3-0ubuntu0.2+pd3.4` | Ubuntu resolute source package `gnome-control-center 1:50.3-0ubuntu0.2` plus the one patch `userpatches/gcc/pidesktop-power-screensaver.patch` (Power panel: a Screensaver group replaces Automatic Screen Blank), built in a resolute chroot by `userpatches/gcc/rebuild-settings.sh`. | GPL-2.0-or-later (parts Expat, CC0-1.0, per Debian copyright) |
| `debs/rhythmbox/rhythmbox_3.5.1-1~pd3_arm64.deb` | `3.5.1-1~pd3` | GNOME release tarball `rhythmbox-3.5.1.tar.xz` from download.gnome.org (SHA-256 checked by the script) plus `userpatches/rhythmbox/patches/0001-prefer-dark-theme.patch`, every optional feature enabled, packaged as one .deb by `userpatches/rhythmbox/build-rhythmbox-deb.sh`. `userpatches/rhythmbox/SHA256SUMS` records the hashes of script, patch and resulting .deb. | GPL-2.0-or-later with the GStreamer plugin exception (upstream `COPYING`) |
| `debs/pipewire/pipewire_*`, `pipewire-bin`, `pipewire-pulse`, `pipewire-alsa`, `pipewire-jack`, `pipewire-audio`, `pipewire-audio-client-libraries`, `libpipewire-0.3-0t64`, `libpipewire-0.3-common`, `libpipewire-0.3-modules`, `libpipewire-0.3-modules-x11`, `libspa-0.2-modules`, `libspa-0.2-bluetooth`, `libspa-0.2-jack`, `libspa-0.2-libcamera`, `gstreamer1.0-pipewire` | `1.6.10-1~pd55` | Upstream PipeWire 1.6.10 (<https://gitlab.freedesktop.org/pipewire/pipewire>, tag `1.6.10`) with Debian's `pipewire 1.6.9-2` packaging (Utopia Maintenance Team), including its CVE-2026-14330 patch, which 1.6.10 does not contain; rebuilt for Ubuntu resolute arm64 with a `~pd55` changelog entry, same build options and binary packages as 5.0's `~pd31`. The complete source package is published with the Plaid Pi 5.5 release at <https://github.com/defcom5-rockchip/pi-desktop>; Debian's packaging: <https://salsa.debian.org/utopia-team/pipewire>. | MIT (Expat); some modules LGPL-2.1+/BSD per Debian copyright |
| `debs/pipewire/wireplumber_*`, `libwireplumber-0.5-0_*` | `0.5.18-1~pd55` | Debian unstable source package `wireplumber 0.5.18-1`, rebuilt for resolute arm64 against the PipeWire above (`~pd55` changelog entry only). Source: `https://deb.debian.org/debian/pool/main/w/wireplumber/wireplumber_0.5.18-1.dsc` / <https://salsa.debian.org/utopia-team/wireplumber>; also published with the Plaid Pi 5.5 release. | MIT (Expat) |
| `debs/media/librockchip-mpp1_*`, `librockchip-mpp-dev_*`, `librockchip-vpu1_*` | `1.5.0+git20260805.a8b19653+ds-0ubuntu1~rk1+pd34` | Rockchip Media Process Platform, upstream <https://github.com/rockchip-linux/mpp>, git `a8b19653` (2026-08-05) via the `~rk1` Ubuntu packaging maintained by Yi Ding (changelog entries from the ysp fork: VP9 show-existing fixes, vepu580 HEVC register fix), built by defcom5-rockchip for resolute with **eight Plaid Pi patches** as quilt patches on top of that packaging (no longer a plain rebuild): seven for AV1 — a padding-OBU tile-offset fix and the deferred reference refresh for stateless (VA-API) front ends that rockchip-vaapi 3.5.0 uses, with two new exported functions (`mpp_av1d_rkva_deferred_refresh()`, `mpp_av1d_rkva_enable()`; additive, soname unchanged) — and one for VP9 (the frame label wraps within 1..0xffff on every SoC, so RK3588 decodes VP9 on both cores with MPP's default number of frames in flight: the form Rockchip's reviewer asked for in <https://github.com/rockchip-linux/mpp/pull/976>, accepted by that reviewer). The complete source package (`.dsc`, `.orig` tarball, `.debian.tar.xz` with the patches and the `~rk1` `debian/` directory) is published with the Plaid Pi 5.5 release at <https://github.com/defcom5-rockchip/pi-desktop>. | Apache-2.0 |
| `debs/media/rockchip-vaapi_3.5.0-1_arm64.deb` | `3.5.0-1` | VA-API driver on top of MPP: <https://github.com/defcom5-rockchip/rockchip-vaapi> release 3.5.0 (<https://github.com/defcom5-rockchip/rockchip-vaapi/releases/tag/v3.5.0>; the .deb there has SHA-256 `ffc541e59e76e73cb77c3bc0bba3a19a32d859225e7b31b9c6af325953e96a91`, the same file as this input). A fork of Eduardo García-Mádico Portabella's `rockchip-vaapi` (copyright both), built for resolute against the MPP package above. | LGPL-2.1-or-later; carries GStreamer's AV1 bit writer (Intel, LGPL-2.0-or-later) in `src/av1/`. |
| `debs/media/mpv_0.41.0-2ubuntu4+pd2_arm64.deb` | `0.41.0-2ubuntu4+pd2` | Ubuntu resolute source package `mpv 0.41.0-2ubuntu4` plus the two patches in `userpatches/mpv/patches/` (zero-copy 8- and 10-bit video on the Mali driver: integer-texture and refused-plane imports in `dmabuf_interop_gl`, and a `vo_gpu` multiplier-printing fix), built by `userpatches/mpv/build-mpv-deb.sh` (details in `userpatches/mpv/README.md`) with Ubuntu's standard compiler flags; `+pd2` packages a `mpv.conf` with a larger cache for network files. Only the `mpv` binary package is installed; `libmpv2` and `libmpv-dev` from the same build are not. The patched source package (`.dsc`, `.orig.tar.gz`, `.debian.tar.xz`) is published with the Plaid Pi 5.5 release. The image holds `mpv`. | GPL-2.0-or-later; as Ubuntu links it (libcdio) the binaries are conveyed under GPL-3.0-or-later. The two patches are LGPL-2.1-or-later. |
| `debs/gst-plugins-good/gstreamer1.0-plugins-good_*`, `gstreamer1.0-gtk3_*`, `gstreamer1.0-pulseaudio_*` | `1.28.2-2ubuntu0.4+pd1` | Ubuntu resolute source package `gst-plugins-good1.0 1.28.2-2ubuntu0.4` plus one upstream patch, GStreamer commit `ef0f99387318d199d6072812c699a3fc59ac994f` ("flacparse: Fix resyncing after a seek", in 1.28.8) applied unchanged (`userpatches/gst-plugins-good/patches/flacparse-fix-resync-after-seek.patch`), built by `userpatches/gst-plugins-good/build-gst-plugins-good-deb.sh`. The recipe installs only `gstreamer1.0-plugins-good`; `gstreamer1.0-gtk3` and `gstreamer1.0-pulseaudio` come out of the same source build and are shipped as inputs so that a user who installs either of them gets the matching `+pd1` version (the three must stay in version lock). The patched source package is published with the Plaid Pi 5.0 and 5.5 releases. Not held: a newer Ubuntu security update replaces it. | LGPL-2.1-or-later |
| `debs/pro-updates/pro-updates_1.5.0_all.deb` | `1.5.0` | Pro Updates, the update window (`pro-updates`, `pro-updates-gui` and its root helper), by the Plaid Pi maintainer: <https://github.com/defcom5-rockchip/pro-updates>, tag `v1.5.0`. An architecture-independent Python/GTK package. | GPL-3.0-or-later |
| `firefox/ffmali/libpidesktop-ffmali.so.1` | 1.1 (sha256 `8c06cd25…`) | `libpidesktop-ffmali`, the library the Firefox launcher loads so the unmodified Firefox can use the hardware decoder's frames on the Mali driver (a refused `GR88`/`RG88` import is retried as `R16`; a plane imported as an integer texture is copied into a normalised one). Complete source next to it: `firefox/ffmali/libpidesktop-ffmali.c`, built by `firefox/ffmali/build.sh`; `firefox/ffmali/README` explains it. The image installs the source in `/usr/share/pi-desktop/firefox/`. Links dynamically against `libmali-hook` and libmali, which it neither contains nor modifies. Not part of Firefox; not made or endorsed by Mozilla. | LGPL-2.1-or-later |

### Pre-built, not rebuilt here

| Input | Version | Origin | Licence |
| --- | --- | --- | --- |
| `debs/media/librga2_*_arm64.deb` | `2.2.0+git20260725.26a50ef-0ubuntu1~rk1` | Rockchip RGA 2D engine library, upstream <https://github.com/rockchip-linux/linux-rga> (`librga-fork` git `26a50ef`), the `~rk1` Ubuntu packaging maintained by Yi Ding. Used as built by that packaging; no Plaid Pi change (no `pd` suffix). Unchanged since 4.0. | Apache-2.0 (bundled libdrm headers Expat; `debian/*` GPL-3+) |
| `debs/libmali-valhall-g610-g24p0-wayland-gbm_1.9-1_arm64.deb` | `1.9-1` | ARM Mali G610 (Valhall) userspace driver, release g24p0, Wayland + GBM variant, as packaged by Rockchip (`libmali` Debian packaging by Jeffy Chen, package maintainer Rockchip; `Homepage: https://github.com/rockchip-linux/libmali`, mirrored as the `libmali` branch of <https://github.com/JeffyCN/mirrors>). Contains the proprietary driver libraries (`libmali.so`, EGL/GLES/OpenCL/Vulkan/GBM front-ends), the Mali CSF firmware `mali_csffw.bin`, and the GPL `libmali-hook`. The recipe pins the package with `apt-mark hold`. Unchanged since 4.0. | Driver and firmware: **ARM End User Licence Agreement** (proprietary; the EULA text is in the package's `copyright` file, `LES-PRE-20769`). `hook/`, `meson`, scripts: GPL-2.0-or-later. |
| `gpu/libmali-hook.so.1.9.0` | sha256 `6ae43aa0…` | The `libmali-hook` shared library from the libmali source tree above (GPL-2.0-or-later, Jeffy Chen), rebuilt with `userpatches/overlay/pidesktop/gpu/0001-libmali-hook-EGL_EXT_device_query-shim-for-Firefox-gfxtest.patch` (a minimal `EGL_EXT_device_query` shim so Firefox's graphics probe accepts the blob). `customize-image.sh` diverts the package's copy and installs this one in its place. The patch is the complete Plaid Pi change; the hook's own source is `hook/` in the libmali repository. Unchanged since 4.0. | GPL-2.0-or-later |
| `usr/share/pi-desktop/screensaver/plaid-penguin-drop.mp4` | 60 s, 3840×2160, H.264 30 fps | Plaid Pi screensaver video (penguins under plaid parachutes), original artwork by defcom5-rockchip; see `ARTWORK.md`. Unchanged since 4.0. | CC BY-SA 4.0 |

## Components outside the inputs that carry non-free terms

| Component | Where it comes from | Licence |
| --- | --- | --- |
| Rockchip boot blobs (DDR init, BL31/`rkbin`) | Pulled by the Armbian framework for the `spl-blobs` boot scenario of the RK3588 U-Boot build. Not in this repository. | Rockchip binary licence (redistributable blobs, as in every RK3588 vendor image) |
| AP6275P WiFi/Bluetooth firmware and NVRAM | `armbian-firmware` (Armbian's firmware package). `customize-image.sh` diverts `nvram_AP6275P.txt` and appends three `btc_params` coexistence lines. | Vendor firmware terms (linux-firmware-style redistribution) |
| Chromium (`xtradeb/apps` PPA) | Installed from the PPA at build time, pinned above Ubuntu's; `etc/chromium.d/pidesktop-vaapi` adds the VA-API flags. | BSD-3-Clause |
| Firefox (`mozillateam/ppa` PPA) | **Not in the image** (Mozilla's distribution policy covers unaltered copies only). The "Firefox" launcher runs `pidesktop-get firefox`, which installs the Mozilla Team build from the PPA on the user's machine, unmodified, and then applies the pieces staged from `overlay/pidesktop/firefox/` (a launcher that loads `libpidesktop-ffmali`, VA-API prefs, neutral policy). | MPL-2.0 |
| Google Chrome | **Not in the image.** The "Google Chrome" launcher runs `pidesktop-chrome`, which offers to download Chrome from Google's signed repository on the user's own machine (Google's terms forbid redistribution). | Google Chrome Terms of Service (user-accepted at download) |
| Ubuntu base, GNOME, Armbian BSP | Ubuntu archive / built by the framework. Plaid Pi renames the product in `/etc/os-release`, the MOTD and `/etc/issue`, removes Armbian's `armbian-config`, `armbian-zsh` and Plymouth theme, and keeps the Armbian BSP (boot scripts, first-login). | Per package; Ubuntu and Armbian trademark policies apply to the names and logos |

## Gaps the maintainer should close before publishing

- **MPP source package**: closed since 5.0. The `+pd34` packages are no longer a plain rebuild (eight patches, see
  the table), and the complete source package — `.dsc`, `.orig` tarball and the `.debian.tar.xz` that holds the
  `~rk1` packaging and the Plaid Pi patches — is published with the Plaid Pi 5.5 release at
  <https://github.com/defcom5-rockchip/pi-desktop>. The patches and `debian/` directory are not duplicated in this
  repository; the source package is the record.
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
