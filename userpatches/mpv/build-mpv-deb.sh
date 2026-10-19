#!/bin/bash
# Build Ubuntu's mpv (26.04 "resolute", source 0.41.0-2ubuntu4) with the Pi-Desktop patches in ./patches as .debs, test suite ON.
#   1. fetch the source package from the Ubuntu archive; verify InRelease (archive key) -> Sources.xz -> every file's SHA256
#   2. unpack fresh, add ./patches/*.patch to debian/patches/series, install ./mpv.conf as debian/mpv.conf.ubuntu (the
#      /etc/mpv/mpv.conf conffile), build without the PipeWire audio output, prepend a +pdN changelog entry
#   3. dpkg-buildpackage -uc -us (source + binaries; the meson test suite runs), copy everything to WORKDIR/out/<version>/
# The source package it produces (.dsc, Ubuntu's .orig.tar.xz, our .debian.tar.xz) is the complete corresponding source.
# Usage:  build-mpv-deb.sh [WORKDIR] [--prepare-only]      No sudo; build deps: sudo bash install-build-deps.sh WORKDIR (once).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
W="${1:-$HOME/Development/mpv/ubuntu-pd}"; MODE="${2:-}"
SRC=mpv; UPV=0.41.0; UBV=0.41.0-2ubuntu4; PDV="$UBV+pd1"
mkdir -p "$W"; bash "$HERE/fetch-ubuntu-source.sh" "$SRC" "$UBV" "$W/src-pkg"
ls "$HERE"/patches/*.patch >/dev/null 2>&1 || { echo "E: no patches in $HERE/patches"; exit 1; }
[ -f "$HERE/mpv.conf" ] || { echo "E: $HERE/mpv.conf (the conffile) missing"; exit 1; }
cd "$W"; rm -rf "$SRC-$UPV"; dpkg-source -q -x "src-pkg/${SRC}_${UBV}.dsc" "$SRC-$UPV" >/dev/null; cd "$SRC-$UPV"
mkdir -p debian/patches
for p in "$HERE"/patches/*.patch; do
    patch -p1 --dry-run -s < "$p" >/dev/null || { echo "E: $(basename "$p") does not apply"; exit 1; }
    patch -p1 -s < "$p"; cp "$p" debian/patches/; basename "$p" >> debian/patches/series
done
patch -p1 -R -s < <(cat $(sed 's|^|debian/patches/|' debian/patches/series | tac))   # dpkg-source applies them itself
install -m644 "$HERE/mpv.conf" debian/mpv.conf.ubuntu
python3 - <<'PY'
import re
c = open('debian/control').read()
c2 = re.sub(r'\n\s*libpipewire-0\.3-dev[^,\n]*,', '', c)
assert c2 != c, 'libpipewire-0.3-dev not found in Build-Depends'
# The conffile turns VA-API zero-copy on, which leaked decoder buffers with drivers before 2.5.0.
stanza = re.search(r'^Package: mpv\n(?:[^\n]+\n)*', c2, re.M)
assert stanza and 'Breaks:' not in stanza.group(0), 'mpv stanza missing or already has Breaks'
c2 = c2.replace(stanza.group(0), stanza.group(0).replace('Architecture: any\n',
    'Architecture: any\nBreaks: rockchip-vaapi (<< 2.5.0~), rockchip-vaapi-driver (<< 2.5.0~)\n', 1), 1)
assert 'Breaks: rockchip-vaapi' in c2, 'Breaks not added'
# On a board with Arm's Mali driver, dh_shlibdeps resolves libEGL/libgbm/libwayland-egl to the libmali package (excluded
# in debian/rules below); depend on what Ubuntu's own mpv and libmpv2 declare instead.
EGL = 'libegl1, libgbm1 (>= 17.1.0~rc2), libwayland-egl1 (>= 1.15.0), '
for pkg in ('mpv', 'libmpv2'):
    st = re.search(r'^Package: %s\n(?:[^\n]+\n)*' % pkg, c2, re.M)
    assert st and 'Depends: ${shlibs:Depends}' in st.group(0), 'Depends of %s not found' % pkg
    c2 = c2.replace(st.group(0), st.group(0).replace('Depends: ${shlibs:Depends}', 'Depends: ' + EGL + '${shlibs:Depends}', 1), 1)
open('debian/control', 'w').write(c2)
r = open('debian/rules').read()
r2 = r.replace('\t\t-Ddvdnav=enabled \\\n', '\t\t-Ddvdnav=enabled \\\n\t\t-Dpipewire=disabled \\\n', 1)
assert r2 != r, 'configure block not found in debian/rules'
assert 'override_dh_shlibdeps' not in r2, 'debian/rules already overrides dh_shlibdeps'
open('debian/rules', 'w').write(r2)
PY
MALI=$(dpkg-query -W -f='${Package}\n' 'libmali-*' 2>/dev/null | head -1 || true)
if [ -n "$MALI" ]; then printf '\noverride_dh_shlibdeps:\n\tdh_shlibdeps -- -x%s\n' "$MALI" >> debian/rules; echo "shlibdeps: excluding $MALI"; fi
{ printf '%s (%s) resolute; urgency=medium\n\n' "$SRC" "$PDV"
  printf '  * Pi-Desktop build for Arm'"'"'s Mali GL driver on RK3588 (Orange Pi 5B):\n'
  printf '    - d/p/0001-hwdec-dmabuf_interop_gl-integer-and-refused-plane-imports:\n'
  printf '      sample a luma plane the GL driver imports as an integer texture (R16\n'
  printf '      as GL_R16UI) as one; copy integer chroma planes and a refused GR88\n'
  printf '      plane (imported as R16) into normalised textures; vo_gpu leaves\n'
  printf '      voluntary dumb mode when such a plane appears. 8- and 10-bit VA-API\n'
  printf '      video then draws zero-copy.\n'
  printf '    - d/p/0002-vo_gpu-keep-integer-texture-divisor-out-of-printed-multiplier:\n'
  printf '      vo_gpu printed its 16-bit integer-texture multiplier with %%f\n'
  printf '      (0.000015 for 1.53e-5), drawing such planes 2 %% dark.\n'
  printf '    - debian/mpv.conf.ubuntu: Pi-Desktop'"'"'s /etc/mpv/mpv.conf (VA-API\n'
  printf '      zero-copy first, OpenGL renderer, audio sync, bilinear chroma).\n'
  printf '    - debian/control: mpv Breaks rockchip-vaapi (<< 2.5.0~) (the conffile\n'
  printf '      turns zero-copy on, which leaked decoder buffers with older drivers).\n'
  printf '    - debian/control, debian/rules: on a build host with Arm'"'"'s Mali driver,\n'
  printf '      depend on libegl1/libgbm1/libwayland-egl1 as Ubuntu'"'"'s build does, not on\n'
  printf '      the libmali package dh_shlibdeps finds.\n'
  printf '    - Built without the PipeWire audio output (-Dpipewire=disabled; no\n'
  printf '      libpipewire-0.3-dev matches the image'"'"'s PipeWire 1.6.9); audio goes\n'
  printf '      through PulseAudio (pipewire-pulse).\n\n'
  printf ' -- defcom5-rockchip <286489597+defcom5-rockchip@users.noreply.github.com>  %s\n\n' "$(date -R)"
  cat debian/changelog; } > debian/changelog.new && mv debian/changelog.new debian/changelog
echo "prepared: $(dpkg-parsechangelog -S Version) with $(wc -l < debian/patches/series) Pi-Desktop patch(es)"
if ! dpkg-checkbuilddeps 2>"$W/unmet.txt"; then echo "build deps missing: $(cat "$W/unmet.txt")"; echo "run  sudo bash $HERE/install-build-deps.sh $W  first"; [ "$MODE" = --prepare-only ] && exit 0 || exit 2; fi
[ "$MODE" = --prepare-only ] && { echo "prepare-only: done"; exit 0; }
export DEB_BUILD_OPTIONS="parallel=$(nproc)"          # tests stay ON (no nocheck)
LOG="$W/build-$PDV.log"; echo "building, log: $LOG"
dpkg-buildpackage -uc -us > "$LOG" 2>&1 || { echo "E: build failed, see $LOG"; tail -30 "$LOG"; exit 1; }
O="$W/out/$PDV"; rm -rf "$O"; mkdir -p "$O"
cp "$W"/*_"$PDV"_*.deb "$W"/*_"$PDV".dsc "$W"/*_"$PDV".debian.tar.xz "$W"/*_"$PDV"_*.buildinfo "$W/src-pkg/${SRC}_${UPV}.orig.tar."* "$O/" 2>/dev/null || true
(cd "$O" && sha256sum * > SHA256SUMS)
echo "tests: $(grep -E '^(Ok|Expected Fail|Fail|Unexpected Pass|Skipped|Timeout):' "$LOG" | tr -s ' ' | paste -sd' ')"
echo "out: $O"; ls "$O"
