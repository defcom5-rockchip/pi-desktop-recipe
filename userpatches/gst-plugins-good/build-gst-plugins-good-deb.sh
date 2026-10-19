#!/bin/bash
# Build Ubuntu's gst-plugins-good1.0 (26.04 "resolute") with the Pi-Desktop patches in ../patches as .debs, test suite ON.
#   1. fetch the source package from the Ubuntu archive; verify InRelease (archive key) -> Sources.xz -> every file's SHA256
#   2. unpack fresh, add ../patches/*.patch to debian/patches/series, prepend a +pdN changelog entry
#   3. dpkg-buildpackage -uc -us (source + binaries; no nocheck: the meson test suite runs), copy them to WORKDIR/out/<version>/
# The source package (.dsc, Ubuntu's .orig.tar.xz, our .debian.tar.xz) is the complete corresponding source.
# Usage:  build-gst-plugins-good-deb.sh [WORKDIR] [--prepare-only | --source-only]      No sudo; build deps: install-build-deps.sh.
#   --source-only builds just the patched source package (no build deps needed). PDDATE="<RFC 2822 date>" sets the
#   changelog entry's date, e.g. to match the binaries already shipped.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; P="$(dirname "$HERE")"
PD="$HERE/patches"; [ -d "$PD" ] || PD="$P/patches"   # recipe layout: patches/ next to this script; project layout: ../patches
ls "$PD"/*.patch >/dev/null 2>&1 || { echo "E: no patches in $PD"; exit 1; }
W="${1:-$HOME/Development/gstreamer/work}"; MODE="${2:-}"
SRC=gst-plugins-good1.0; UPV=1.28.2; UBV=1.28.2-2ubuntu0.4; PDV="$UBV+pd1"
ARCHIVE=https://ports.ubuntu.com/ubuntu-ports; POCKETS="resolute-security resolute-updates"; KEYRING=/usr/share/keyrings/ubuntu-archive-keyring.gpg
mkdir -p "$W/index" "$W/src"; cd "$W/index"
want=""
for pocket in $POCKETS; do
  curl -fsS -o "InRelease-$pocket" "$ARCHIVE/dists/$pocket/InRelease"
  gpgv --keyring "$KEYRING" --output "Release-$pocket" "InRelease-$pocket" 2>/dev/null || { echo "E: bad signature on $pocket InRelease"; exit 1; }
  curl -fsS -o "Sources-$pocket.xz" "$ARCHIVE/dists/$pocket/main/source/Sources.xz"
  h=$(awk '/^SHA256:/{f=1;next} /^[^ ]/{f=0} f && $3=="main/source/Sources.xz"{print $1}' "Release-$pocket")
  [ "$(sha256sum < "Sources-$pocket.xz" | cut -d' ' -f1)" = "$h" ] || { echo "E: Sources.xz hash mismatch ($pocket)"; exit 1; }
  ent=$(xz -dc "Sources-$pocket.xz" | awk -v RS= -v s="$SRC" -v v="$UBV" 'index($0, "Package: " s "\n")==1 && index($0, "\nVersion: " v "\n")')
  if [ -n "$ent" ]; then want=$(printf '%s\n' "$ent" | awk '/^Checksums-Sha256:/{f=1;next} /^[^ ]/{f=0} f{print $1, $3}'); echo "index: $SRC $UBV found in $pocket (signature + hashes OK)"; break; fi
done
[ -n "$want" ] || { echo "E: $SRC $UBV is not in $POCKETS any more (superseded?): bump UBV/PDV and check the patches still apply"; exit 1; }
cd "$W/src"
while read -r sum name; do
  if [ -f "$name" ] && echo "$sum  $name" | sha256sum -c --status -; then continue; fi
  curl -fsS -o "$name" "$ARCHIVE/pool/main/g/$SRC/$name"
  echo "$sum  $name" | sha256sum -c --quiet - || { echo "E: $name hash mismatch"; exit 1; }
done <<< "$want"
echo "source: $(echo "$want" | wc -l) files verified against the signed index"
rm -rf "$SRC-$UPV"; dpkg-source -x "${SRC}_${UBV}.dsc" >/dev/null; cd "$SRC-$UPV"
for p in "$PD"/*.patch; do cp "$p" debian/patches/; basename "$p" >> debian/patches/series; patch -p1 --dry-run -s < "$p" >/dev/null || { echo "E: $(basename "$p") does not apply"; exit 1; }; done
{ printf '%s (%s) resolute; urgency=medium\n\n' "$SRC" "$PDV"
  printf '  * debian/patches/flacparse-fix-resync-after-seek.patch: backport upstream\n'
  printf '    ef0f9938 (1.28.8) "flacparse: Fix resyncing after a seek". Seeking in a\n'
  printf '    FLAC file without a SEEKTABLE could take an invalid frame for a valid\n'
  printf '    frame of size 0 and stop playback ("Internal data stream error").\n'
  printf '    GStreamer work item 5314.\n\n'
  printf ' -- defcom5-rockchip <286489597+defcom5-rockchip@users.noreply.github.com>  %s\n\n' "${PDDATE:-$(date -R)}"
  cat debian/changelog; } > debian/changelog.new && mv debian/changelog.new debian/changelog
echo "prepared: $(dpkg-parsechangelog -S Version) with $(ls "$PD"/*.patch | wc -l) Pi-Desktop patch(es)"
if [ "$MODE" != --source-only ] && ! dpkg-checkbuilddeps 2>/tmp/gst-unmet.$$; then echo "build deps missing ($(tr ' ' '\n' < /tmp/gst-unmet.$$ | grep -c -- '-dev\|debhelper') or more): run  sudo bash $HERE/install-build-deps.sh  first"; rm -f /tmp/gst-unmet.$$; [ "$MODE" = --prepare-only ] && exit 0 || exit 2; fi
[ "$MODE" = --prepare-only ] && { echo "prepare-only: done"; exit 0; }
O="${OUT:-$W/out}/$PDV"; mkdir -p "$O"
if [ "$MODE" = --source-only ]; then
  cd "$W/src" && dpkg-source -q -b "$SRC-$UPV" >/dev/null && cp "${SRC}_${PDV}.dsc" "${SRC}_${PDV}.debian.tar.xz" "${SRC}_${UPV}.orig.tar."* "$O/"
  (cd "$O" && sha256sum * > SHA256SUMS); echo "source package: $O"; ls "$O"; exit 0
fi
export DEB_BUILD_OPTIONS="parallel=$(nproc)"          # tests stay ON (no nocheck)
LOG="$W/build-$PDV.log"; echo "building, log: $LOG"
dpkg-buildpackage -uc -us > "$LOG" 2>&1 || { echo "E: build failed, see $LOG"; tail -30 "$LOG"; exit 1; }
cp "$W"/src/*_"$PDV"_*.deb "$W/src/${SRC}_${PDV}.dsc" "$W/src/${SRC}_${PDV}.debian.tar.xz" "$W/src/${SRC}_${UPV}.orig.tar."* "$O/"; (cd "$O" && sha256sum * > SHA256SUMS)
echo "tests: $(grep -E '^(Ok|Expected Fail|Fail|Unexpected Pass|Skipped|Timeout):' "$LOG" | tr -s ' ' | paste -sd' ')"
echo "flacparse check: $(grep -E 'elements_flacparse +(OK|FAIL|SKIP|TIMEOUT|EXPECTEDFAIL)' "$LOG" | tr -s ' ')"
echo "debs: $O ($(ls "$O"/*.deb | wc -l) packages)"
