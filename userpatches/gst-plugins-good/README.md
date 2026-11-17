# gst-plugins-good for Pi-Desktop

**Superseded in Plaid Pi 6.5:** the image ships GStreamer `1.28.9-0ubuntu0~pd1` (core, base, good, bad, ugly, libav; 27
runtime packages under `overlay/pidesktop/debs/gstreamer/`), built by `userpatches/backports-2026-11/run-backports.sh`.
The flacparse fix below is upstream since 1.28.8, so the `+pd1` rebuild is no longer needed; this folder stays as the
4.5–6.0 record. 1.28.9 leaves the opencore AMR plugins out, as Ubuntu's packaging does (`universe`); AMR still decodes
through gst-libav.

Pi-Desktop 4.5 ships Ubuntu 26.04's `gst-plugins-good1.0` source package `1.28.2-2ubuntu0.4` rebuilt with one upstream
patch as `1.28.2-2ubuntu0.4+pd1` (binary packages gstreamer1.0-plugins-good, gstreamer1.0-gtk3, gstreamer1.0-pulseaudio).

**Why:** GStreamer 1.28.2's FLAC parser could stop playback with "Internal data stream error" when seeking in a FLAC
file without a seek table (common for vinyl rips and downloads); Rhythmbox seeks that way. The patch is upstream commit
`ef0f99387318d199d6072812c699a3fc59ac994f` (1.28.8, "flacparse: Fix resyncing after a seek", Sebastian Dröge), applied
unchanged: `patches/flacparse-fix-resync-after-seek.patch`.

**Build:** `sudo bash install-build-deps.sh`, then `bash build-gst-plugins-good-deb.sh [WORKDIR]`. The script fetches the
Ubuntu source package and verifies it through the signed archive index, adds the patch to `debian/patches/series`,
prepends the `+pd1` changelog entry and runs `dpkg-buildpackage -b` with the test suite on. It also leaves the patched
source tree in WORKDIR; `dpkg-source -b` on it produces the patched source package (`.dsc`, `.orig.tar.xz`,
`.debian.tar.xz`) that is published with the Pi-Desktop release.

**Licence:** LGPL-2.1-or-later (the patch is upstream's). Not held on the image: a newer Ubuntu security update of
gst-plugins-good replaces it, and the first-boot check reports which build is present.
