#!/bin/bash
# Build rhythmbox_3.5.1-1~pd3_arm64.deb for Pi Desktop 3.0 "Plaid".
# Upstream GNOME 3.5.1 tarball (sha256-checked) + patches/0001-prefer-dark-theme.patch, every optional feature
# enabled, installed to /usr, packaged as ONE .deb that replaces Ubuntu's split rhythmbox packages.
# Needs the build deps (see BUILD_DEPS below; apt install them first). Runs as a normal user; installs nothing.
# Usage: bash build-rhythmbox-deb.sh [workdir]      → <workdir>/rhythmbox_3.5.1-1~pd3_arm64.deb
set -euo pipefail

UPV=3.5.1
PKGV=$UPV-1~pd3
ARCH=arm64
MAINT="defcom5-rockchip <286489597+defcom5-rockchip@users.noreply.github.com>"
URL=https://download.gnome.org/sources/rhythmbox/${UPV%.*}/rhythmbox-$UPV.tar.xz
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(realpath -m "${1:-$HERE/work}")"
SRC=$WORK/rhythmbox-$UPV
ST=$WORK/staging
MA=$(dpkg-architecture -qDEB_HOST_MULTIARCH)

BUILD_DEPS="meson ninja-build gettext itstool yelp-tools valac gi-docgen gobject-introspection \
libgirepository1.0-dev libgirepository-2.0-dev libcairo2-dev libgdk-pixbuf-2.0-dev libgstreamer1.0-dev \
libgstreamer-plugins-base1.0-dev libgtk-3-dev libjson-glib-dev libpeas-dev libsoup-3.0-dev libxml2-dev libtdb-dev \
libtotem-plparser-dev libgudev-1.0-dev check libsecret-1-dev python-gi-dev libgpod-dev libmtp-dev libnotify-dev \
liblirc-dev libbrasero-media3-dev libdmapsharing-4.0-dev libgrilo-0.3-dev libx11-dev dpkg-dev file"
missing=$(for p in $BUILD_DEPS; do dpkg -s "$p" >/dev/null 2>&1 || echo "$p"; done)
[[ -z $missing ]] || { echo "E: missing build deps, run:  sudo apt install --no-install-recommends" $missing; exit 1; }

echo "=== source"
mkdir -p "$WORK" && cd "$WORK"
[[ -f rhythmbox-$UPV.tar.xz ]] || curl -sfLO "$URL"
curl -sfL "${URL%.tar.xz}.sha256sum" | grep "rhythmbox-$UPV.tar.xz" | sha256sum -c -
rm -rf "$SRC" && tar xf rhythmbox-$UPV.tar.xz
for p in "$HERE"/patches/*.patch; do echo "patch: ${p##*/}"; patch -d "$SRC" -p1 --no-backup-if-mismatch < "$p"; done

echo "=== configure (all features forced on: a missing dependency is an error, not a silent skip)"
meson setup "$SRC/build" "$SRC" --prefix=/usr --buildtype=release --auto-features=enabled \
	-Ddaap=enabled -Dsample-plugins=true -Dapidoc=true -Dhelp=true > "$WORK/setup.log"
sed -n '/^rhythmbox /,/User defined options/p' "$WORK/setup.log"

echo "=== build + test"
ninja -C "$SRC/build" > "$WORK/build.log"
meson test -C "$SRC/build" > "$WORK/test.log" || { tail -20 "$WORK/test.log"; exit 1; }
grep -E '^(Ok|Fail):' "$WORK/test.log"

echo "=== stage"
rm -rf "$ST" && DESTDIR="$ST" meson install -C "$SRC/build" --no-rebuild > "$WORK/install.log"
ELFS=$(find "$ST" -type f -exec sh -c 'file -b "$1" | grep -q ELF && echo "$1"' _ {} \;)
strip --strip-unneeded --remove-section=.comment --remove-section=.note $ELFS
gzip -9n "$ST"/usr/share/man/man1/*.1
install -m0644 "$SRC/COPYING" "$ST/usr/share/doc/rhythmbox/copyright"
printf 'rhythmbox (%s) resolute; urgency=medium\n\n  * New upstream release %s, built from the GNOME release tarball with\n    all optional features enabled.\n  * Prefer the dark GTK theme variant by default (0001-prefer-dark-theme).\n  * Single package replacing Ubuntu'"'"'s split rhythmbox packages.\n\n -- %s  %s\n' \
	"$PKGV" "$UPV" "$MAINT" "$(TZ=America/Phoenix date -R)" | gzip -9n > "$ST/usr/share/doc/rhythmbox/changelog.Debian.gz"

echo "=== dependencies"
mkdir -p "$WORK/debian"
printf 'Source: rhythmbox\n\nPackage: rhythmbox\nArchitecture: %s\n' $ARCH > "$WORK/debian/control"
echo 'librhythmbox-core 10 rhythmbox (>= 3.5.1)' > "$WORK/debian/shlibs.local"
SHLIBS=$(cd "$WORK" && dpkg-shlibdeps -O -xrhythmbox -l"$ST/usr/lib/$MA" $ELFS 2>/dev/null | sed 's/^shlibs:Depends=//')
# python plugins need girepository-2.0-aware libpeas (>= 1.38); shlibdeps only sees >= 1.0.0
SHLIBS=${SHLIBS/libpeas-1.0-1 (>= 1.0.0)/libpeas-1.0-1 (>= 1.38)}
RUNTIME="dbus, media-player-info, gstreamer1.0-plugins-base (>= 1.4.0), gstreamer1.0-plugins-good (>= 1.4.0), python3, \
python3-gi (>= 3.53), gir1.2-glib-2.0, gir1.2-gtk-3.0, gir1.2-pango-1.0, gir1.2-gdkpixbuf-2.0, gir1.2-peas-1.0 (>= 1.38), \
gir1.2-gstreamer-1.0, gir1.2-gst-plugins-base-1.0, gir1.2-secret-1, gir1.2-soup-3.0"
OTHERS="rhythmbox-data, rhythmbox-plugins, rhythmbox-plugin-cdrecorder, rhythmbox-plugin-zeitgeist, librhythmbox-core10, gir1.2-rb-3.0, rhythmbox-dev, rhythmbox-doc"
PROV=$(echo "$OTHERS" | sed "s/\([a-z0-9.+-]*\)\(,\|$\)/\1 (= $PKGV)\2/g")

echo "=== package"
mkdir -p "$ST/DEBIAN"
cat > "$ST/DEBIAN/control" <<EOF
Package: rhythmbox
Version: $PKGV
Architecture: $ARCH
Maintainer: $MAINT
Installed-Size: $(cd "$ST" && find usr \( -type f -o -type l \) -printf '%s\n' | awk '{k+=int(($1+1023)/1024)} END{print k}')
Depends: $SHLIBS, $RUNTIME
Recommends: gstreamer1.0-libav, gstreamer1.0-plugins-ugly, gstreamer1.0-plugins-bad, gvfs-backends, grilo-plugins-0.3, yelp, avahi-daemon
Suggests: gir1.2-zeitgeist-2.0, brasero
Conflicts: $OTHERS
Replaces: $OTHERS
Provides: $PROV
Section: gnome
Priority: optional
Homepage: https://gitlab.gnome.org/GNOME/rhythmbox
Description: music player and organizer for GNOME (Pi Desktop build, dark by default)
 Rhythmbox $UPV built from the upstream GNOME release with every optional
 feature enabled: Python and Vala plugins, DAAP sharing, iPod and MTP
 devices, CD burning, FM radio, LIRC, Grilo, notifications, libsecret,
 user help and API documentation, plus the sample plugins.
 .
 Pi Desktop change: the app requests the dark variant of the GTK theme by
 default (patch 0001-prefer-dark-theme).
 .
 This single package replaces Ubuntu's split rhythmbox packages.
EOF
echo 'activate-noawait ldconfig' > "$ST/DEBIAN/triggers"
(cd "$ST" && find usr -type f -exec md5sum {} + > DEBIAN/md5sums)
dpkg-deb --root-owner-group -Zxz --build "$ST" "$WORK/rhythmbox_${PKGV}_$ARCH.deb"
echo "=== DONE: $WORK/rhythmbox_${PKGV}_$ARCH.deb"
