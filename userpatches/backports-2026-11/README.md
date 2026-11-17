# Backports built for Plaid Pi 6.5 (November 2026)

The pre-built packages under `overlay/pidesktop/debs/media/` (mpv, libmpv2, libplacebo387, libdvdread8t64) and
`overlay/pidesktop/debs/gstreamer/` (the 27 GStreamer 1.28.9 runtime packages) were built with the script in this
folder, for arm64 / Ubuntu 26.04 "resolute", in a qemu-user chroot on an x86-64 PC. `sources/<pkg>/` holds the
patched source packages as `.dsc` + `.debian.tar.xz`; the upstream tarballs (`ORIG-SHA256SUMS` lists their
checksums) are published with the Plaid Pi 6.5 release next to the image, and the `.dsc` files name them.
`BUILT-SHA256SUMS` lists the resulting `.deb` files.

## Run

    bash run-backports.sh                 # one sudo prompt, then unattended (hours under qemu)
    ONLY="libplacebo mpv" bash run-backports.sh
    REBUILD=1 bash run-backports.sh       # ignore finished packages
    CHECK=1 bash run-backports.sh         # run the test suites (slow under qemu)

The script creates the arm64 26.04 build chroot (`debootstrap --variant=buildd` through `qemu-user-static`) at
`./chroot-resolute-arm64` next to the script (`CH=` overrides) on first use, then builds `sources/*` in dependency
order: libplacebo → libdvdread → mpv → gstreamer1.0 → base → good → bad → ugly → libav. Each package's result is
installed into the chroot before the next one builds against it. Results land in `out/<pkg>/`, logs in `logs/`.
On Ubuntu 26.04 the chroot commands get their stdin from `/dev/null` and apt runs with `-o Dpkg::Use-Pty=0`:
26.04's `sudo` (sudo-rs) otherwise runs them in a pty of its own, where the frontend lock dialogue freezes.

## Sources

| package | version | base packaging | changes |
|---|---|---|---|
| libplacebo | `7.387.0-1~pd2` | Debian experimental `7.387.0-1` | debhelper-compat 14 → 13 (26.04 has 13); `-Dlibdovi=disabled` and libdovi-dev dropped: 26.04's `libdovi-dev` 3.3.2-3 ships an empty `rpu_parser.h` on arm64 and 26.04's own libplacebo has no libdovi either |
| libdvdread | `7.1.1-1~pd1` | Debian sid `7.1.1-1` | rebuilt for resolute (compat 13); 7.1.1 brings the DVD-Audio reading mpv's `dvda://` needs |
| mpv | `0.42.0-1~pd4` | Ubuntu 26.04 `0.41.0-2ubuntu4` packaging on the upstream 0.42.0 tarball | the two Plaid Pi patches (`userpatches/mpv/patches/`, integer-texture imports on the Mali driver) refreshed with exact context; `-Ddvda=enabled` (Build-Depends `libdvdread-dev (>= 7.1.1)`); the native PipeWire audio output built in (`ao=pipewire,alsa` in the packaged `mpv.conf`, the file the image installs as `/etc/mpv/mpv.conf`); libcurl off |
| gstreamer1.0, gst-plugins-base1.0, gst-plugins-good1.0, gst-plugins-bad1.0, gst-plugins-ugly1.0, gst-libav1.0 | `1.28.9-0ubuntu0~pd1` | Ubuntu 26.04's `1.28.2` packaging on the upstream 1.28.9 tarballs (26.10's 1.28.8 packaging needs GIR -dev packages 26.04 lacks) | `libgstreamer1.0-0.symbols`: `gst_check_run_suite_nofork@Base 1.28.9` added (new symbol; Ubuntu's `dpkg-gensymbols -c4` fails on any new symbol), base and bad switched to `-c1`; bad: `libgsthip.so.*` → `libgsthip-1.0.so.*` in `debian/rules` (upstream rename in 1.28.7); every Ubuntu CVE patch of the 1.28.2 packaging checked to be included upstream in 1.28.9 and dropped; AMR (opencore) plugins stay disabled as in Ubuntu's packaging (`universe`); tests off under qemu (`CHECK=1` runs them) |

Why these versions: libplacebo 7.387 is what mpv 0.42 wants; mpv 0.42 opens DVD and Blu-ray folder copies in place
and brings the Wayland presentation fixes; GStreamer 1.28.9 carries the FLAC-seek fix Plaid Pi 6.0 patched into
`gst-plugins-good +pd1`, the decodebin3 crash fix and two security follow-ups Ubuntu 26.04 lacks
(GStreamer-SA-2026-0049 and -0074, without CVE ids). `~pd1`/`~pd4` sort below any future Ubuntu update of the same
upstream version, so an Ubuntu security update of 1.28.9 would replace these packages; mpv and libmpv2 are held in
the image instead, because Ubuntu's mpv lacks the Mali patches.

Builds are reproducible from `sources/` with the upstream tarballs; `BUILT-SHA256SUMS` is the record of the
packages the Plaid Pi 6.5 image ships. Licences: as upstream (mpv GPL-2.0-or-later, conveyed GPL-3.0-or-later as
Ubuntu links it; libplacebo LGPL-2.1-or-later; libdvdread GPL-2.0-or-later; GStreamer LGPL-2.1-or-later with some
GPL plugins); this script and README are GPL-3.0-or-later like the rest of the recipe.
