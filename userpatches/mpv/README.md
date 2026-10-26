# mpv for Pi-Desktop

Pi-Desktop 4.5 ships Ubuntu 26.04's mpv source package `0.41.0-2ubuntu4` rebuilt with two patches as
`0.41.0-2ubuntu4+pd2` (binary packages `mpv`, `libmpv2`; `libmpv-dev` is built too). It links Ubuntu's libplacebo
(`libplacebo360`) like Ubuntu's own build.

Plaid Pi 6.0 ships `0.41.0-2ubuntu4+pd3`: the `+pd2` binaries unchanged, repacked with a new `mpv.conf`
(`vd-lavc-film-grain=cpu`, so AV1 film grain is applied by the decoder: by Plaid Pi's MPP in hardware, by dav1d in
software). libplacebo's grain shader does not compile on the Mali driver for 10-bit video (the luma plane is an integer
texture there), which dropped the grain and failed the first frame. Its source package is `+pd2`'s with
`debian/mpv.conf.ubuntu` and `debian/changelog` changed; `build-mpv-deb.sh` still builds `+pd2`, so a full rebuild must
carry the new `mpv.conf` (this folder's copy) and the new version.

**Why:** Arm's proprietary Mali GL driver on the Orange Pi 5B imports the brightness plane of a 10-bit frame
(`DRM_FORMAT_R16`) as an integer texture, which a video shader reads as 0, and refuses the two-channel 8-bit colour
plane of an 8-bit frame (`GR88`) outright (rockchip-vaapi KNOWN-ISSUES KI-11). Ubuntu's mpv therefore draws 10-bit
zero-copy video near-black and cannot draw 8-bit zero-copy at all.

**The patches** (`patches/`, DEP-3 headers that say what the AI assistant did):

- `0001-hwdec-dmabuf_interop_gl-integer-and-refused-plane-imports.patch` (`video/out/hwdec/dmabuf_interop_gl.c`,
  `video/out/gpu/video.c`): a brightness plane imported as a one-channel integer texture of its own depth is sampled as
  one (no copy); a colour plane imported as an integer texture is copied into a normalised texture; a refused `GR88`
  plane is imported as `R16` (the same bytes) and copied into `RG8`. `vo=gpu` leaves its voluntary "dumb mode" (for
  example with `--profile=fast`) when such a plane appears, because dumb mode would sample it unfiltered.
- `0002-vo_gpu-keep-integer-texture-divisor-out-of-printed-multiplier.patch` (`video/out/gpu/video.c`): `vo=gpu`
  printed its integer-texture multiplier with `%f` (`0.000015` for 1.53e-5) and drew 16-bit integer planes 2 % dark.
  A general mpv bug, which the integer sampling exposed.

8-bit and 10-bit video then draws zero-copy: 8-bit pictures identical to copy-back decoding, 10-bit within one 8-bit
step on a few per cent of pixels with no bias. Known limit: gpu-next with `--scaler-resizes-only=no` plus a crop, pan
or zoom routes the integer plane into a linear-filtered scaler; libplacebo then falls back to a simpler scaler.

**Packaging changes** (made by `build-mpv-deb.sh`, listed in the package changelog): `debian/mpv.conf.ubuntu` is
replaced by `mpv.conf` here (Pi-Desktop's `/etc/mpv/mpv.conf`: the recipe's overlay `mpv.conf` with its zero-copy
transform applied, so the file the image installs equals the conffile and upgrades never prompt); the PipeWire audio
output is off (`-Dpipewire=disabled`: Ubuntu's `libpipewire-0.3-dev` conflicts with the PipeWire the image holds; audio
goes through pipewire-pulse); `mpv` declares `Breaks: rockchip-vaapi (<< 2.5.0~)`; and on a build host with the Mali
driver, `mpv` and `libmpv2` depend on `libegl1`, `libgbm1` and `libwayland-egl1` as Ubuntu's build does, not on the
libmali package. Everything else is Ubuntu's build, including its options (Ubuntu builds mpv without its unit tests).

**Build** (on Ubuntu 26.04 arm64): `bash build-mpv-deb.sh WORKDIR --prepare-only` (fetches Ubuntu's source package and
verifies it through the signed archive index, then prepares the tree), `sudo bash install-build-deps.sh WORKDIR` once,
then `bash build-mpv-deb.sh WORKDIR`. It runs `dpkg-buildpackage -uc -us` and copies the binary packages and the
patched source package to `WORKDIR/out/<version>/`.

**Licences:** mpv is GPL-2.0-or-later in its default configuration (Ubuntu's copyright file has the details); as
Ubuntu builds it, linked with libcdio (GPL-3.0-or-later), the binaries are conveyed under GPL-3.0-or-later. The patches
change LGPL-2.1-or-later files and are LGPL-2.1-or-later. These scripts are GPL-3.0-or-later
like the rest of the recipe. **Complete corresponding source:** the patched source package (`mpv_0.41.0-2ubuntu4+pd3.dsc`,
Ubuntu's `mpv_0.41.0.orig.tar.gz`, `mpv_0.41.0-2ubuntu4+pd3.debian.tar.xz`), published with the Pi-Desktop release
that ships these packages.

**Updates:** the image holds `mpv`, because any Ubuntu update of mpv (`0.41.0-2ubuntu4.x` sorts above `+pd3`) would
replace it and draw 10-bit near-black with Pi-Desktop's configuration. Ubuntu's mpv fixes therefore arrive with a
Pi-Desktop rebuild: bump `UBV`/`PDV` in `build-mpv-deb.sh`, check that the patches still apply, rebuild, retest.
