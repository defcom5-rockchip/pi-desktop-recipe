#!/bin/bash
# Pi-Desktop backports, November 2026: libplacebo 7.387 -> mpv 0.42 -> GStreamer 1.28.9 (core, base, good, bad, ugly, libav),
# built for arm64 / Ubuntu 26.04 "resolute" in a qemu-user chroot on this PC. One sudo prompt at the start, then unattended
# (sudo ticket kept alive like build-both-5b.sh). Re-runnable: finished packages (out/<pkg>/*.deb) are skipped.
#
#   bash userpatches/backports-2026-11/run-backports.sh         # everything in sources/ in dependency order
#   ONLY="libplacebo mpv" bash .../run-backports.sh              # a subset
#   REBUILD=1 ...                                                # ignore out/ and build again
#
# Inputs : sources/<pkg>/{*.dsc, *.orig.tar.*, *.debian.tar.xz}   (prepared on the PC; ORIG-SHA256SUMS lists the upstream tarballs)
# Output : out/<pkg>/*.deb + *.changes + *.buildinfo, build logs in logs/, this run's log run-<date>.log (run-latest.log symlink)
# Chroot : ./chroot-resolute-arm64 next to this script, or CH=/path (debootstrap --variant=buildd, created on first run, kept for later backports)
# Tests  : DEB_BUILD_OPTIONS="nocheck" by default (GStreamer's suites take hours under qemu and are flaky there);
#          CHECK=1 runs them. Real tests belong on a board anyway.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; SRC="$HERE/sources"; OUT="$HERE/out"; LOGS="$HERE/logs"
CH="${CH:-$HERE/chroot-resolute-arm64}"; MIRROR="https://ports.ubuntu.com/ubuntu-ports"
ORDER="libplacebo libdvdread mpv gstreamer1.0 gst-plugins-base1.0 gst-plugins-good1.0 gst-plugins-bad1.0 gst-plugins-ugly1.0 gst-libav1.0"
JOBS="${JOBS:-$(nproc)}"; mkdir -p "$OUT" "$LOGS"
RUNLOG="$HERE/run-$(date +%Y%m%d-%H%M).log"; ln -sfn "$RUNLOG" "$HERE/run-latest.log"; exec > >(tee -a "$RUNLOG") 2>&1
say() { echo "$(date +%H:%M:%S) $*"; }

[ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] || { echo "E: no qemu-aarch64 binfmt (install qemu-user-static)"; exit 1; }
sudo -v || exit 1
( while sleep 60; do sudo -n -v 2>/dev/null || exit; done ) & KEEP=$!
cleanup() { kill "$KEEP" 2>/dev/null || true; sudo umount "$CH/proc" "$CH/dev/pts" "$CH/sys" 2>/dev/null || true; }
trap cleanup EXIT

# stdin from /dev/null: with no tty on any fd, sudo-rs (26.04) runs the command WITHOUT its own pty. Inside that pty the
# foreground process group never matched apt-get's, so apt-get's final tcsetattr() drew SIGTTOU and froze (2026-11-07, libplacebo).
inch() { sudo chroot "$CH" /usr/bin/env -i HOME=/root PATH=/usr/sbin:/usr/bin:/sbin:/bin LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive "$@" </dev/null; }
mounts() { sudo mount -t proc proc "$CH/proc" 2>/dev/null || true; sudo mount -t sysfs sys "$CH/sys" 2>/dev/null || true
           sudo mkdir -p "$CH/dev/pts"; sudo mount -t devpts devpts "$CH/dev/pts" 2>/dev/null || true; }

# ------------------------------------------------------------------ 1. chroot (once)
if [ ! -x "$CH/usr/bin/dpkg" ]; then
	say "creating the arm64 resolute build chroot at $CH"
	sudo debootstrap --arch=arm64 --variant=buildd --include=ca-certificates,fakeroot,apt-utils,eatmydata resolute "$CH" "$MIRROR"
	sudo tee "$CH/etc/apt/sources.list.d/ubuntu.sources" >/dev/null <<-EOF
	Types: deb
	URIs: $MIRROR
	Suites: resolute resolute-updates resolute-security
	Components: main restricted universe multiverse
	Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
	EOF
	sudo rm -f "$CH/etc/apt/sources.list"
	printf 'APT::Install-Recommends "0";\nAcquire::Languages "none";\n' | sudo tee "$CH/etc/apt/apt.conf.d/90build" >/dev/null
	mounts; inch apt-get update -qq; inch apt-get -y -qq -o Dpkg::Use-Pty=0 install build-essential fakeroot devscripts equivs
	inch useradd -m -s /bin/bash builder
	say "chroot ready"
fi
mounts; inch apt-get update -qq

# ------------------------------------------------------------------ 2. packages, in dependency order
for p in $ORDER; do
	[ -n "${ONLY:-}" ] && [[ " $ONLY " != *" $p "* ]] && continue
	dsc=$(ls "$SRC/$p"/*.dsc 2>/dev/null | head -1) || true
	[ -n "$dsc" ] || { say "$p: no .dsc in sources/$p, skipped"; continue; }
	if [ -z "${REBUILD:-}" ] && ls "$OUT/$p"/*.deb >/dev/null 2>&1; then
		say "$p: already built (out/$p), installing its debs into the chroot for the next stages"
		sudo rm -rf "$CH/home/builder/$p-out"; sudo cp -r "$OUT/$p" "$CH/home/builder/$p-out"
		inch bash -c "apt-get -y -qq -o Dpkg::Use-Pty=0 install /home/builder/$p-out/*.deb >/dev/null" || say "W: $p: reinstall into chroot failed"
		continue
	fi
	say "== $p: $(basename "$dsc")"
	sudo rm -rf "$CH/home/builder/$p"; sudo mkdir -p "$CH/home/builder/$p"; sudo cp "$SRC/$p"/* "$CH/home/builder/$p/"
	sudo chown -R 1000:1000 "$CH/home/builder/$p" 2>/dev/null || true
	say "$p: build-dep"
	inch bash -c "cd /home/builder/$p && apt-get -y -qq -o Dpkg::Use-Pty=0 build-dep ./$(basename "$dsc")" > "$LOGS/$p-builddep.log" 2>&1 \
		|| { say "E: $p: build-dep failed, see logs/$p-builddep.log"; tail -5 "$LOGS/$p-builddep.log"; exit 1; }
	say "$p: dpkg-buildpackage -j$JOBS (log: logs/$p-build.log)"
	opts="parallel=$JOBS"; [ -z "${CHECK:-}" ] && opts="$opts nocheck"
	t0=$(date +%s)
	inch su builder -c "cd /home/builder/$p && dpkg-source -x *.dsc src >/dev/null && cd src && DEB_BUILD_OPTIONS='$opts' dpkg-buildpackage -us -uc -b -j$JOBS" > "$LOGS/$p-build.log" 2>&1 \
		|| { say "E: $p: build FAILED after $(( ($(date +%s)-t0)/60 )) min, see logs/$p-build.log"; grep -n -E 'error:|Error [0-9]|FAILED|dh_missing' "$LOGS/$p-build.log" | tail -15; exit 1; }
	mkdir -p "$OUT/$p"; rm -f "$OUT/$p"/*
	sudo cp "$CH/home/builder/$p"/*.deb "$CH/home/builder/$p"/*.changes "$CH/home/builder/$p"/*.buildinfo "$OUT/$p/" 2>/dev/null
	sudo chown "$(id -u):$(id -g)" "$OUT/$p"/*
	say "$p: built in $(( ($(date +%s)-t0)/60 )) min: $(ls "$OUT/$p"/*.deb | wc -l) debs"
	# later stages build against this one (mpv needs libplacebo-dev 7.387; gst modules need the 1.28.9 -dev packages)
	inch bash -c "apt-get -y -qq -o Dpkg::Use-Pty=0 install /home/builder/$p/*.deb >/dev/null" || { say "E: $p: installing the result into the chroot failed"; exit 1; }
done
(cd "$OUT" && sha256sum */*.deb > SHA256SUMS)
say "all done: $(ls "$OUT"/*/*.deb | wc -l) debs under $OUT (SHA256SUMS written)"
