#!/bin/bash
# Rebuild Pi-Desktop's patched GNOME Settings (gnome-control-center 1:50.3-0ubuntu0.2+pd3.4) with the Plaid Pi
# Screensaver wording. Builds in an Ubuntu 26.04 "workshop" folder (/srv/pd3-build) and creates it first if it isn't
# there (first run ~10 min: download + build; later runs ~2 min). Where the workshop lives:
#   Plaid booted from SD  -> on the spare eMMC (mounted for the build, unmounted at the end; its OS is not changed)
#   Plaid running on eMMC -> /srv/pd3-build on the running system
# Output: the three .debs next to this script. Progress is also written to rebuild-settings.log here.
# Run:  sudo bash rebuild-settings.sh
# Nothing is installed on the running system except the small 'debootstrap' tool if it is missing.
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "run it with sudo:  sudo bash $0"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
exec > >(tee "$HERE/rebuild-settings.log") 2>&1
PATCH="$HERE/pidesktop-power-screensaver.patch"
UBU="1:50.3-0ubuntu0.2"; VER="$UBU+pd3.4"
M=/mnt/emmc; C=$M/srv/pd3-build; SRC=/root/gcc/gnome-control-center-50.3; DEV=/dev/mmcblk0p1
MIRROR=http://ports.ubuntu.com/ubuntu-ports
[[ -f $PATCH ]] || { echo "E: $PATCH missing"; exit 1; }
ON_EMMC=0; [[ "$(findmnt -no SOURCE /)" == "$DEV" ]] && { ON_EMMC=1; M=/; C=/srv/pd3-build; echo "=== running from the eMMC: workshop is $C on this system"; }

mounted_here=()
cleanup() { for ((i=${#mounted_here[@]}-1; i>=0; i--)); do umount "${mounted_here[$i]}" 2>/dev/null; done; }
trap cleanup EXIT
if [[ $ON_EMMC == 0 ]]; then
	[[ -b $DEV ]] || { echo "E: no eMMC partition $DEV"; exit 1; }
	if ! mountpoint -q $M; then mkdir -p $M && mount $DEV $M && mounted_here+=("$M") || { echo "E: cannot mount $DEV"; exit 1; }; fi
fi
echo "=== $(date +%T) eMMC: $(df -h $M | awk 'NR==2{print $4" free"}')"

# ---- 1. the workshop (an Ubuntu 26.04 build root), only if it is missing
if [[ ! -x $C/usr/bin/apt-get ]]; then
	echo "=== $(date +%T) creating the workshop at /srv/pd3-build on the eMMC (debootstrap resolute, ~5 min)"
	command -v debootstrap >/dev/null || apt-get install -y -qq debootstrap >/dev/null || { echo "E: cannot install debootstrap"; exit 1; }
	mkdir -p $C
	debootstrap --variant=buildd --components=main,universe resolute $C $MIRROR || { echo "E: debootstrap failed"; exit 1; }
fi
for d in proc sys dev dev/pts; do
	mountpoint -q $C/$d || { mount --bind /$d $C/$d && mounted_here+=("$C/$d"); }
done
rm -f $C/etc/resolv.conf; cat /etc/resolv.conf > $C/etc/resolv.conf
cat > $C/etc/apt/sources.list <<S
deb $MIRROR resolute main universe
deb $MIRROR resolute-updates main universe
deb $MIRROR resolute-security main universe
deb-src $MIRROR resolute main universe
deb-src $MIRROR resolute-updates main universe
deb-src $MIRROR resolute-security main universe
S
install -m0644 "$PATCH" $C/root/pidesktop-power-screensaver.patch
mkdir -p $C/root/gcc; rm -f $C/root/gcc/*.deb $C/root/gcc/*.buildinfo $C/root/gcc/*.changes

# ---- 2. tools, build dependencies and the Ubuntu source (skipped quickly when already there)
echo "=== $(date +%T) build tools + dependencies (first run downloads a lot; later runs are quick)"
chroot $C /bin/bash -c "set -e -o pipefail; export LC_ALL=C.UTF-8 DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends devscripts quilt equivs dpkg-dev fakeroot libdistro-info-perl ca-certificates >/dev/null
apt-get build-dep -y -qq gnome-control-center=$UBU >/dev/null
if [ ! -d $SRC ]; then cd /root/gcc && apt-get source -qq gnome-control-center=$UBU; fi
echo \"source: \$(cd $SRC && dpkg-parsechangelog -S Version | sed 's/+pd3.*//')\"" || { echo "E: preparing the workshop failed"; exit 1; }

# ---- 3. apply our patch and build
echo "=== $(date +%T) building $VER (the whole log scrolls below)"
chroot $C /bin/bash -c "set -e -o pipefail; export LC_ALL=C.UTF-8 DEBIAN_FRONTEND=noninteractive DEBFULLNAME=defcom5-rockchip DEBEMAIL=286489597+defcom5-rockchip@users.noreply.github.com QUILT_PATCHES=debian/patches
cd $SRC
grep -qx pidesktop-power-screensaver.patch debian/patches/series || echo pidesktop-power-screensaver.patch >> debian/patches/series
[ \"\$(quilt top 2>/dev/null)\" = debian/patches/pidesktop-power-screensaver.patch ] && quilt pop -q >/dev/null || true
cp /root/pidesktop-power-screensaver.patch debian/patches/pidesktop-power-screensaver.patch
quilt push -a -q >/dev/null || [ \"\$(quilt top)\" = debian/patches/pidesktop-power-screensaver.patch ]
echo \"quilt: top patch \$(quilt top)\"
grep -q 'uses a screensaver instead of blanking the screen' panels/power/cc-power-panel.blp
dpkg-parsechangelog -S Version | grep -qF '$VER' || dch -b -v '$VER' --distribution resolute 'Pi-Desktop: Power panel shows a Screensaver group (screensaver service settings) in place of Automatic Screen Blank. Wording: Pi-Desktop uses a screensaver instead of blanking the screen.'
echo \"version: \$(dpkg-parsechangelog -S Version)\"
export DEB_BUILD_OPTIONS='nocheck parallel=8'
rm -f debian/files   # stale entries from an earlier +pd3.x build make dpkg-genchanges fail after the debs are built
dpkg-buildpackage -b -uc -us -nc 2>&1 | tee /root/gcc/build.log"
rc=$?

n=0
for p in gnome-control-center gnome-control-center-data gnome-control-center-faces; do
	f=$(ls $C/root/gcc/${p}_*${VER#*+}*.deb 2>/dev/null | head -1)
	[[ -n $f ]] && install -m0644 "$f" "$HERE/" && n=$((n+1))
done
echo
if [[ $rc -eq 0 && $n -eq 3 ]]; then
	echo "=== $(date +%T) DONE: 3 debs copied here:"; ls -la "$HERE"/*${VER#*+}*.deb
	echo "Done — nothing was installed on this system."
else
	echo "=== $(date +%T) FAILED (build rc=$rc, $n/3 debs). Last lines of the log:"; tail -15 $C/root/gcc/build.log 2>/dev/null
fi
