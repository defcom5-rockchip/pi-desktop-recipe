#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 defcom5-rockchip (Pi-Desktop). See LICENSE in the recipe repository.
# Pi-Desktop 4.0 layer — runs as root inside the arm64 rootfs chroot at the end of Armbian's customize step.
# Args: RELEASE LINUXFAMILY BOARD BUILD_DESKTOP. Overlay (userpatches/overlay) is bind-mounted read-only at /tmp/overlay.
RELEASE=$1; LINUXFAMILY=$2; BOARD=$3; BUILD_DESKTOP=$4
OV=/tmp/overlay/pidesktop
PDV="${PIDESKTOP_VERSION:-$(cat /etc/pi-desktop-release 2>/dev/null)}"; PDV="${PDV:-4.0 Plaid}"   # set by the config hook pre_customize_image__pidesktop_version
GPU="${PIDESKTOP_GPU_STACK:-mali}"
export DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none
log() { echo "I: [pi-desktop] $*"; }
warn() { echo "W: [pi-desktop] $*" >&2; }
# safe_purge PKG... — purge only if apt would remove exactly the named packages and nothing else. Lesson of the first
# 4.0 bake (2026-10-03): `apt-get purge -y ubuntu-wallpapers` silently took gnome-shell, gdm3 and the session with it
# (Ubuntu's gnome-shell Depends on ubuntu-wallpapers) and the image booted to a root console. Never purge blind again.
safe_purge() {
	local want=() extra sim p
	for p in "$@"; do dpkg -s "$p" >/dev/null 2>&1 && want+=("$p"); done
	[[ ${#want[@]} -gt 0 ]] || { log "purge: none of [$*] installed"; return 0; }
	sim=$(apt-get -s purge "${want[@]}" 2>&1 | awk '/^Remv /{print $2}' | sed 's/:.*//' | sort -u)
	extra=$(comm -23 <(printf '%s\n' "$sim") <(printf '%s\n' "${want[@]}" | sort -u))
	if [[ -n $extra ]]; then
		warn "purge of [${want[*]}] REFUSED — apt would also remove: $(echo $extra)"
		return 1
	fi
	apt-get purge -y -qq "${want[@]}" >/dev/null 2>&1 && log "purged: ${want[*]}" || { warn "purge of [${want[*]}] failed"; return 1; }
}

[[ "$RELEASE" == "resolute" ]] || { warn "customize-image: RELEASE=$RELEASE, this layer is written for resolute — skipping"; exit 0; }

# ---------------------------------------------------------------- apt: ports over https, universe on
for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list; do
	[[ -f $f ]] && sed -i 's|http://ports.ubuntu.com|https://ports.ubuntu.com|g' "$f"
done
apt-get update -qq || warn "apt update failed (https ports?)"

# ---------------------------------------------------------------- audio: ONE server (pipewire), not two (ary11 deadlock)
# configng gnome.yaml keeps pulseaudio in the resolute block (only trixie/forky/sid swap to pipewire).
# The purge takes pulseaudio-utils (pactl) with it; it is reinstalled below — pactl is a client only (no daemon) and
# pidesktop-headphone-follow needs it (test2 first boot: jack following silently dead without it). rtkit = RT for PipeWire.
apt-get purge -y -qq pulseaudio pulseaudio-module-bluetooth pulseaudio-utils 2>/dev/null || true
apt-get install -y -qq --no-install-recommends pipewire pipewire-pulse pipewire-audio pipewire-jack pipewire-alsa \
	wireplumber libspa-0.2-bluetooth libspa-0.2-jack alsa-ucm-conf alsa-utils gstreamer1.0-pipewire \
	pulseaudio-utils rtkit >/dev/null \
	|| warn "pipewire stack install had errors"
if ls "$OV"/debs/pipewire/*.deb >/dev/null 2>&1; then
	# PipeWire 1.6.9 + WirePlumber 0.5.17 (Debian sid packaging rebuilt for resolute arm64) — ABI-compatible bump over 1.6.2/0.5.13
	apt-get install -y -qq --allow-downgrades "$OV"/debs/pipewire/*.deb >/dev/null \
		&& log "pipewire/wireplumber from overlay: $(dpkg-query -W -f='${Version}' pipewire) / $(dpkg-query -W -f='${Version}' wireplumber)" \
		|| warn "overlay pipewire debs failed to install — image stays on stock $(dpkg-query -W -f='${Version}' pipewire)"
	for p in pipewire pipewire-bin libpipewire-0.3-0t64 libpipewire-0.3-modules libspa-0.2-modules libspa-0.2-bluetooth pipewire-pulse pipewire-audio pipewire-jack pipewire-alsa wireplumber libwireplumber-0.5-0; do
		dpkg -s "$p" >/dev/null 2>&1 && apt-mark hold "$p" >/dev/null 2>&1
	done
else
	log "no overlay pipewire debs — stock $(dpkg-query -W -f='${Version}' pipewire 2>/dev/null)"
fi
install -d /etc/pipewire/pipewire.conf.d /etc/wireplumber/wireplumber.conf.d
# install -o root, never cp -a: the overlay is owned by the build user (uid 1000), which is the desktop user on the
# image — cp -a left six /etc files user-writable on test3 (incl. modprobe.d = root code exec on module load).
install -m0644 -o root -g root "$OV"/etc/pipewire/pipewire.conf.d/*.conf -t /etc/pipewire/pipewire.conf.d/ 2>/dev/null
install -m0644 -o root -g root "$OV"/etc/wireplumber/wireplumber.conf.d/*.conf -t /etc/wireplumber/wireplumber.conf.d/ 2>/dev/null
# rtkit for the audio group whatever the login timing (GDM starts PipeWire ~9 s before the seat session → polkit said no)
install -Dm0644 -o root -g root "$OV"/etc/polkit-1/rules.d/60-pidesktop-rtkit-audio.rules /etc/polkit-1/rules.d/60-pidesktop-rtkit-audio.rules \
	&& log "polkit: rtkit allowed for group audio (PipeWire RT independent of login timing)" || warn "rtkit polkit rule missing"
# GUI password prompts (found by Plaid Claude on the test7 eMMC, 2026-09-27): polkit >= 126 runs its agent helper through
# polkit-agent-helper.socket, and that helper needs SO_PEERPIDFD (Linux 6.5+). The 6.1 vendor kernel lacks it, so every
# helper exits 1 ("Pidfd not supported on this platform"); GNOME Shell retries without end and never draws the password
# box. Every pkexec / Settings / Software prompt hangs, and ~45 min of retries (systemd at 59 % CPU) locked up the desktop.
# Mask the socket so libpolkit-agent falls back to the classic helper, and make that helper setuid via dpkg-statoverride
# (survives polkitd upgrades). Proven live on the Plaid. UNDO both on a >= 6.5 kernel, where the socket route is the safer one.
PAH=/usr/lib/polkit-1/polkit-agent-helper-1
if [[ -x $PAH && -e /usr/lib/systemd/system/polkit-agent-helper.socket ]]; then
	systemctl mask polkit-agent-helper.socket >/dev/null 2>&1 || true
	dpkg-statoverride --list "$PAH" >/dev/null 2>&1 || dpkg-statoverride --update --add root root 4755 "$PAH"
	[[ -u $PAH && $(readlink /etc/systemd/system/polkit-agent-helper.socket) == /dev/null ]] \
		&& log "polkit: setuid agent helper, socket masked (6.1 kernel has no SO_PEERPIDFD)" \
		|| warn "polkit: agent-helper fix incomplete — GUI password prompts will hang"
fi
systemctl --global enable pipewire pipewire-pulse wireplumber >/dev/null 2>&1 || true
systemctl --global mask pulseaudio.service pulseaudio.socket >/dev/null 2>&1 || true
dpkg -l | grep -q '^ii  pulseaudio ' && warn "pulseaudio STILL installed" || log "audio: pipewire $(dpkg-query -W -f='${Version}' pipewire) + wireplumber $(dpkg-query -W -f='${Version}' wireplumber), pulseaudio gone"

# ---------------------------------------------------------------- GPU userspace (THE test): libmali G610 g24p0 on kbase g29p1
if [[ "$GPU" == "mali" ]]; then
	MALI=$(ls "$OV"/debs/libmali-valhall-g610-g24p0-wayland-gbm_*_arm64.deb 2>/dev/null | sort -V | tail -1)   # wayland-gbm: the x11 variant segfaults in eglGetDisplay(wl_display*) (Firefox probe)
	if [[ -n $MALI ]]; then
		apt-get install -y -qq "$MALI" >/dev/null && log "libmali: $(dpkg-query -W -f='${Package} ${Version}' 'libmali-valhall-g610-*')" || warn "libmali install FAILED"
		ldconfig
		# Firefox's graphics probe hard-requires EGL_EXT_device_query, which no Mali blob has: JeffyCN libmali-hook + a
		# device-query shim (v1, sha 6ae43aa0…, patch in overlay/gpu). NEVER ship an instrumented hook — it crashed the gdm greeter.
		HOOK=/usr/lib/aarch64-linux-gnu/libmali-hook.so.1.9.0
		if [[ -f "$OV"/gpu/libmali-hook.so.1.9.0 && -f $HOOK ]]; then
			dpkg-divert --quiet --add --rename --divert "$HOOK.libmali" "$HOOK" && install -m0644 "$OV"/gpu/libmali-hook.so.1.9.0 "$HOOK" && ldconfig
			log "libmali-hook: device-query shim installed ($(sha256sum "$HOOK" | cut -c1-12))"
			apt-mark hold "$(dpkg-query -W -f='${Package}' 'libmali-valhall-g610-*-wayland-gbm' 2>/dev/null)" >/dev/null 2>&1   # a repo libmali must not replace the tested blob
		else
			warn "libmali-hook shim NOT installed — Firefox will run in software"
		fi
		# Ubuntu's gdm greeter runs as dynamic users; uaccess ACLs are the only thing that reaches them (seeed's finding:
		# otherwise mutter dies "Failed to create gbm device" -> "No GPUs found").
		cat > /etc/udev/rules.d/50-mali-dma-heap.rules <<-'R'
			SUBSYSTEM=="dma_heap", GROUP="render", MODE="0660", TAG+="uaccess"
			SUBSYSTEM=="drm", KERNEL=="renderD*", TAG+="uaccess"
			KERNEL=="mali0", GROUP="render", MODE="0660", TAG+="uaccess"
		R
		for u in gdm Debian-gdm; do id "$u" >/dev/null 2>&1 && usermod -aG render,video "$u"; done
		# glvnd may still pick Mesa's EGL for some clients; publish the Mali ICD alongside so EGL_PLATFORM lookups find it
		install -d /usr/share/glvnd/egl_vendor.d
		[[ -f /usr/share/glvnd/egl_vendor.d/00_mali.json ]] || cat > /usr/share/glvnd/egl_vendor.d/00_mali.json <<-'J'
			{ "file_format_version" : "1.0.0", "ICD" : { "library_path" : "/usr/lib/aarch64-linux-gnu/mali/libEGL.so.1" } }
		J
	else
		warn "PIDESKTOP_GPU_STACK=mali but no libmali deb in overlay — image will fall to llvmpipe"
	fi
else
	log "GPU stack = $GPU (stock Mesa left alone; expect llvmpipe on the vendor kernel — control build)"
fi
# X11 fallback sessions: modesetting on rockchip DRM
install -d /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/10-rockchip-kms.conf <<-'X'
	Section "OutputClass"
	    Identifier "RockchipDRM"
	    MatchDriver "rockchip"
	    Driver "modesetting"
	    Option "PrimaryGPU" "yes"
	EndSection
X

# ---------------------------------------------------------------- decode: patched MPP (+ matching -dev), rockchip-vaapi 2.2.0, mpv 0.41 + our conf
apt-get install -y -qq --no-install-recommends libva2 libva-drm2 libva-wayland2 libva-x11-2 vainfo libdrm2 mpv ffmpeg v4l-utils >/dev/null || warn "media base install had errors"
if ls "$OV"/debs/media/*.deb >/dev/null 2>&1; then
	apt-get install -y -qq --allow-downgrades "$OV"/debs/media/*.deb >/dev/null && log "media debs: $(cd "$OV"/debs/media && ls *.deb | sed 's/_arm64.deb//' | tr '\n' ' ')" || warn "media overlay debs failed"
	for p in librockchip-mpp1 librockchip-mpp-dev librockchip-vpu1 rockchip-vaapi rockchip-vaapi-driver librga2 libv4l-rkmpp; do dpkg -s "$p" >/dev/null 2>&1 && apt-mark hold "$p" >/dev/null; done
else
	warn "no media debs in overlay (patched MPP / rockchip-vaapi not baked) — decode tests will be stock-only"
fi
install -d /etc/mpv
install -m0644 -o root -g root "$OV"/etc/mpv/mpv.conf /etc/mpv/mpv.conf 2>/dev/null && log "mpv $(dpkg-query -W -f='${Version}' mpv) + /etc/mpv/mpv.conf (display-resample, vaapi)"
[[ -f /etc/environment ]] && grep -q LIBVA_DRIVER_NAME /etc/environment || echo 'LIBVA_DRIVER_NAME=rockchip' >> /etc/environment

# ---------------------------------------------------------------- browsers: Chromium (xtradeb) + Chrome (Google arm64) = 8-bit HW video; Firefox (mozillateam) = GPU + 10-bit HW — no snaps
apt-get install -y -qq --no-install-recommends software-properties-common >/dev/null
add-apt-repository -y ppa:xtradeb/apps >/dev/null 2>&1 && log "ppa: xtradeb/apps" || warn "xtradeb PPA add failed"
add-apt-repository -y ppa:mozillateam/ppa >/dev/null 2>&1 && log "ppa: mozillateam/ppa" || warn "mozillateam PPA add failed"
cat > /etc/apt/preferences.d/pidesktop-browsers <<-'P'
	Package: chromium chromium-*
	Pin: release o=LP-PPA-xtradeb-apps
	Pin-Priority: 1001

	Package: firefox firefox-*
	Pin: release o=LP-PPA-mozillateam
	Pin-Priority: 1001

	Package: firefox chromium chromium-browser
	Pin: release o=Ubuntu*
	Pin-Priority: -1
P
apt-get update -qq
apt-get install -y -qq --no-install-recommends chromium chromium-sandbox >/dev/null && log "browsers: chromium $(dpkg-query -W -f='${Version}' chromium)" || warn "chromium install had errors"
# Firefox is NOT in the image (4.0, 2026-10-03): Mozilla's distribution policy allows unaltered copies only, and ours carries a
# launcher, prefs and a policy file. It is a first-click installer instead (pidesktop-get firefox): the Mozilla Team build
# from the PPA pinned above, with the Mali/VA-API pieces below applied on the user's own machine. Purge any copy a tier left.
dpkg -s firefox >/dev/null 2>&1 && { apt-get purge -y -qq firefox >/dev/null 2>&1 && log "firefox: removed from the image (first-click installer instead)" || warn "firefox purge failed"; }
install -d /etc/chromium.d
install -m0644 -o root -g root "$OV"/etc/chromium.d/* -t /etc/chromium.d/ 2>/dev/null
# Firefox on the blob: private libGL = Mali GLES (Firefox dlsym()s GL from libGL first; glvnd's copy returns NULL for a Mali
# EGL context), wrapper ahead of /usr/bin in PATH, VA-API prefs. Result on hardware: WebRender + WebGL on the GPU, 10-bit
# HEVC/VP9 zero-copy; 8-bit video stays software (blob has no GR88 dma-buf format) — Chrome/Chromium are the 8-bit HW path.
# The pieces are staged under /usr/share/pi-desktop/firefox and applied by pidesktop-install-app after the user installs
# Firefox; only the Mali libGL shim directory (two symlinks, no Firefox code) is prepared here.
install -d /usr/local/lib/pidesktop-firefox-mali
ln -sfn /usr/lib/aarch64-linux-gnu/mali/libGLESv2.so.2 /usr/local/lib/pidesktop-firefox-mali/libGL.so
ln -sfn /usr/lib/aarch64-linux-gnu/mali/libGLESv2.so.2 /usr/local/lib/pidesktop-firefox-mali/libGL.so.1
install -d /usr/share/pi-desktop/firefox
install -m0755 -o root -g root "$OV"/firefox/firefox /usr/share/pi-desktop/firefox/firefox
install -m0644 -o root -g root "$OV"/firefox/vaapi.js "$OV"/firefox/policies.json -t /usr/share/pi-desktop/firefox/
log "firefox: Mali libGL shim dir + launcher/prefs/policy staged for the first-click installer"
# Google Chrome is NOT in the image: Google's terms make its licence personal and forbid redistribution (licensing review
# 2026-09-26). A "Google Chrome" launcher (same desktop id, shadows the package's) runs pidesktop-chrome: if Chrome is
# missing it offers to download it from Google's signed apt repo (key pinned: EB4C1BFD…D38B4796) via pkexec, then opens
# Chrome with the VA-API flags (8-bit HW video, GPU compositing, flicker-free on the blob). Chrome reads no flags dir,
# so the flags live in the wrapper, where Chrome updates can't strip them.
install -Dm0755 -o root -g root "$OV"/usr/local/bin/pidesktop-chrome /usr/local/bin/pidesktop-chrome
install -Dm0755 -o root -g root "$OV"/usr/local/sbin/pidesktop-install-chrome /usr/local/sbin/pidesktop-install-chrome
install -Dm0644 -o root -g root "$OV"/usr/local/share/applications/google-chrome.desktop /usr/local/share/applications/google-chrome.desktop
install -Dm0644 -o root -g root "$OV"/usr/share/polkit-1/actions/org.pidesktop.install-chrome.policy /usr/share/polkit-1/actions/org.pidesktop.install-chrome.policy
dpkg -s google-chrome-stable >/dev/null 2>&1 && warn "google-chrome-stable is installed in the image — it must not be shipped" || log "chrome: not shipped; first-run installer launcher in place"

# ---------------------------------------------------------------- apps that install on first click (test9, 2026-10-02)
# The image left Armbian's "full" desktop tier (DESKTOP_TIER=mid) to get under GitHub's 2 GiB release-file limit: test8 was
# 2.26 GB compressed, of which Microsoft's VS Code build alone was 243 MB, LibreOffice 133 MB plus a 58 MB Java runtime it
# dragged in, Thunderbird 74 MB. LibreOffice, GIMP, Inkscape, Thunderbird and VSCodium keep their place in the app grid as
# placeholders that download the real app from its own repository on the first click (the Chrome pattern: pkexec, and a
# pinned signing key for the one third-party repo, VSCodium's). The installer removes the placeholder once the real menu
# entry exists. VSCodium replaces VS Code on purpose: Microsoft's build ships with telemetry enabled (product.json
# enableTelemetry=true) under Microsoft's licence, which the README's "No telemetry" promise can't carry.
install -Dm0755 -o root -g root "$OV"/usr/local/bin/pidesktop-get /usr/local/bin/pidesktop-get
install -Dm0755 -o root -g root "$OV"/usr/local/sbin/pidesktop-install-app /usr/local/sbin/pidesktop-install-app
install -Dm0644 -o root -g root "$OV"/usr/share/polkit-1/actions/org.pidesktop.install-app.policy /usr/share/polkit-1/actions/org.pidesktop.install-app.policy
for d in libreoffice-startcenter gimp org.inkscape.Inkscape thunderbird codium firefox; do
	install -Dm0644 -o root -g root "$OV"/usr/local/share/applications/$d.desktop /usr/local/share/applications/$d.desktop
done
install -d /usr/share/icons/hicolor/scalable/apps
install -m0644 -o root -g root "$OV"/usr/share/icons/hicolor/scalable/apps/pidesktop-get-*.svg -t /usr/share/icons/hicolor/scalable/apps/
gtk-update-icon-cache -q -f /usr/share/icons/hicolor 2>/dev/null || true
# nothing from the full tier may ride along (a stale staging dir or a yaml change would bring it back silently)
FULLP=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' libreoffice-core libreoffice-common gimp inkscape thunderbird code 2>/dev/null | awk '$1 ~ /^[ih]i/ {print $2}')
if [[ -n $FULLP ]]; then warn "full-tier apps present in a mid-tier image: $FULLP"; else log "apps: mid tier; LibreOffice, GIMP, Inkscape, Thunderbird, VSCodium and Firefox install on first click"; fi
# Audacity stays in the image: small, and this is an audio box. The mid tier doesn't carry it.
apt-get install -y -qq audacity >/dev/null 2>&1 && log "audacity: $(dpkg-query -W -f='${Version}' audacity)" || warn "audacity install failed"
snap list >/dev/null 2>&1 && warn "snapd present: $(snap list 2>/dev/null | tail -n +2 | awk '{print $1}' | tr '\n' ' ')"

# ---------------------------------------------------------------- default browser = Chromium (Chrome is not shipped; the Chrome
# launcher offers "make default" after the user installs it). The Google Chrome branch below only applies to a local image
# where Chrome was installed by hand.
# Chrome/Chromium are the 8-bit hardware-video browsers on the blob and flicker-free; Firefox installs on first click (GPU + 10-bit).
if [[ -x /usr/bin/google-chrome-stable ]]; then BR=google-chrome.desktop; BRBIN=/usr/bin/google-chrome-stable; else BR=chromium.desktop; BRBIN=/usr/bin/chromium; fi
install -d /etc/xdg
cat > /etc/xdg/mimeapps.list <<-M
	[Default Applications]
	x-scheme-handler/http=$BR
	x-scheme-handler/https=$BR
	text/html=$BR
	application/xhtml+xml=$BR
	x-scheme-handler/about=$BR
	x-scheme-handler/unknown=$BR
M
# video = mpv for every video type it declares: without an explicit default the mimeinfo order decides (on test3,
# 2026-09-24, a VLC launcher override won it; VLC is gone since 2026-09-26, but any other video app could do the same).
if [[ -f /usr/share/applications/mpv.desktop ]]; then
	grep -oP '^MimeType=\K.*' /usr/share/applications/mpv.desktop | tr ';' '\n' | grep '^video/' | sed 's/$/=mpv.desktop/' >> /etc/xdg/mimeapps.list
	log "video default: mpv for $(grep -c '=mpv.desktop' /etc/xdg/mimeapps.list) video types"
fi
for a in x-www-browser gnome-www-browser; do update-alternatives --set $a "$BRBIN" >/dev/null 2>&1 || true; done
# dock + desktop icons (Pi Claude's 2.0.x-look layout, Chrome first); later dconf files override Armbian's 00-bg
install -Dm0644 "$OV"/etc/dconf/db/local.d/10-pidesktop-shell /etc/dconf/db/local.d/10-pidesktop-shell
# default wallpaper (set in 10-pidesktop-shell) + listed in Settings > Appearance
install -Dm0644 "$OV"/backgrounds/penguin-drop-plaid-v2-3840x2160.png /usr/share/backgrounds/pi-desktop/penguin-drop-plaid-v2-3840x2160.png
install -Dm0644 "$OV"/backgrounds/pi-desktop-wallpapers.xml /usr/share/gnome-background-properties/pi-desktop-wallpapers.xml
# Files: "Open in Terminator" on the right-click menu (Files 50 has no Open in Terminal; Terminator ships no Files
# integration; Ubuntu has no open-any-terminal package). Small nautilus-python add-on, tested against Files 50 (2026-09-26).
if apt-get install -y -qq --no-install-recommends python3-nautilus >/dev/null 2>&1; then
	install -Dm0644 -o root -g root "$OV"/usr/share/nautilus-python/extensions/pidesktop-open-terminator.py \
		/usr/share/nautilus-python/extensions/pidesktop-open-terminator.py && log "Files: Open in Terminator add-on"
else
	warn "python3-nautilus install failed — no Open in Terminator in Files"
fi
# Terminator look (Plaid Claude, approved live 2026-09-26): navy/cream/orange Plaid palette, Ubuntu Sans Mono 13, window
# 1480x800 = 147 cols, room for the fastfetch greeting (its info column starts at col 78). Replaces the transparent-black skel config Armbian's desktop base lays
# down. Skel, not /etc/xdg: a user config always wins over the system one (no merge), and Terminator only reads the first
# existing $XDG_CONFIG_DIRS entry. Reaches new accounts only.
install -Dm0644 -o root -g root "$OV"/etc/skel/.config/terminator/config /etc/skel/.config/terminator/config && log "terminator: Plaid config in /etc/skel"
# Session killed by systemd-oomd during a big copy (2026-09-26): Nautilus is D-Bus activated without a systemd unit,
# so it ran inside the session bus's cgroup (dbus.service); the copy's page cache was charged there and oomd killed
# dbus.service -> whole GNOME session gone (systemd#35270, LP#2075104; systemd leaves the grouping to the distro).
# Fix: Files in its own user unit (via a /usr/local D-Bus override, searched before /usr/share) + a cap on unwritten
# data so NAS -> SD-card copies can't pile up gigabytes of dirty pages. oomd's own policy (50%/20 s) stays as shipped.
install -Dm0644 -o root -g root "$OV"/etc/systemd/user/org.gnome.Nautilus.service /etc/systemd/user/org.gnome.Nautilus.service
install -Dm0644 -o root -g root "$OV"/usr/local/share/dbus-1/services/org.gnome.Nautilus.service /usr/local/share/dbus-1/services/org.gnome.Nautilus.service
install -Dm0644 -o root -g root "$OV"/etc/sysctl.d/60-pidesktop-writeback.conf /etc/sysctl.d/60-pidesktop-writeback.conf
log "session safety: Nautilus in its own user unit (oomd can't hit the session bus) + writeback cap (dirty 256M/64M)"
# Quick how-to on every new desktop (user, 2026-09-26): getting Chrome (first-run installer) + display scaling at 4K@120.
install -Dm0644 -o root -g root "$OV/etc/skel/Desktop/Pi-Desktop How-To.txt" "/etc/skel/Desktop/Pi-Desktop How-To.txt" && log "desktop: Pi-Desktop How-To.txt in /etc/skel/Desktop"
# suspend: masked + GNOME auto-suspend off (2.0.x hook 60 rule; carry-forward miss found on test2 first boot 2026-09-24).
# Resume on the vendor kernel is not validated on Plaid (the stmmac fix is in, the sleep DT config is not). Blanking stays.
for t in sleep suspend hibernate hybrid-sleep; do systemctl mask "$t.target" >/dev/null 2>&1; done
install -Dm0644 "$OV"/etc/dconf/db/local.d/05-pidesktop-power /etc/dconf/db/local.d/05-pidesktop-power
# login screen at every boot after first-run setup (Armbian's own autologin off-switch never fires)
install -Dm0644 "$OV"/etc/systemd/system/pidesktop-login-screen.service /etc/systemd/system/pidesktop-login-screen.service
systemctl enable pidesktop-login-screen.service >/dev/null 2>&1 && log "login screen: autologin removed after first-run setup" || warn "login-screen service enable failed"
# ---------------------------------------------------------------- screensaver instead of screen blank
# The display does not come back after a blank at 4K@120 Hz (board hard-hangs on the monitor's standby hotplug,
# 2026-09-24). GNOME's screen blank is locked off; a per-user service shows a screensaver (picture/slideshow/video
# from ~/Pictures/screensaver via mpv) after its own delay and holds an idle inhibitor while it shows and while the
# session is locked (GNOME would still blank a locked screen). Settings > Power shows a "Screensaver" group in place
# of "Automatic Screen Blank" — a patched gnome-control-center (debs/gcc, built from the patch in userpatches/gcc/).
install -Dm0644 -o root -g root "$OV"/etc/dconf/db/local.d/locks/pidesktop-power /etc/dconf/db/local.d/locks/pidesktop-power
# the GDM greeter has its own session (stock: blank 5 min, suspend 20 min); gdm's generate-config compiles /usr/share/gdm/dconf/* at every start
install -Dm0644 -o root -g root "$OV"/usr/share/gdm/dconf/50-pidesktop-no-blank /usr/share/gdm/dconf/50-pidesktop-no-blank
install -m0755 -o root -g root "$OV"/usr/local/bin/pidesktop-screensaverd -t /usr/local/bin/
install -Dm0644 -o root -g root "$OV"/usr/share/glib-2.0/schemas/org.pidesktop.screensaver.gschema.xml /usr/share/glib-2.0/schemas/org.pidesktop.screensaver.gschema.xml
glib-compile-schemas /usr/share/glib-2.0/schemas/ 2>/dev/null || warn "glib-compile-schemas failed (screensaver settings)"
install -Dm0644 -o root -g root "$OV"/etc/systemd/user/pidesktop-screensaver.service /etc/systemd/user/pidesktop-screensaver.service
install -d -o root -g root /usr/share/pi-desktop/screensaver
install -m0644 -o root -g root "$OV"/usr/share/pi-desktop/screensaver/*.mp4 -t /usr/share/pi-desktop/screensaver/ 2>/dev/null || warn "screensaver video missing from overlay"
install -d /etc/skel/Pictures/screensaver
ln -sfn /usr/share/pi-desktop/screensaver/plaid-penguin-drop.mp4 /etc/skel/Pictures/screensaver/plaid-penguin-drop.mp4
ln -sfn /usr/share/backgrounds/pi-desktop/penguin-drop-plaid-v2-3840x2160.png /etc/skel/Pictures/screensaver/plaid-penguins.png
systemctl --global enable pidesktop-screensaver.service >/dev/null 2>&1 && log "screensaver: service enabled, GNOME blank locked off" || warn "screensaver service enable failed"
if ls "$OV"/debs/gcc/gnome-control-center_*_arm64.deb >/dev/null 2>&1; then
	apt-get install -y -qq --allow-downgrades "$OV"/debs/gcc/gnome-control-center_*.deb "$OV"/debs/gcc/gnome-control-center-data_*.deb "$OV"/debs/gcc/gnome-control-center-faces_*.deb >/dev/null \
		&& log "settings: gnome-control-center $(dpkg-query -W -f='${Version}' gnome-control-center) (Power > Screensaver group)" || warn "patched gnome-control-center failed to install"
	for p in gnome-control-center gnome-control-center-data gnome-control-center-faces; do dpkg -s "$p" >/dev/null 2>&1 && apt-mark hold "$p" >/dev/null 2>&1; done
else
	warn "no patched gnome-control-center in overlay/debs/gcc — Power panel will show the stock Screen Blank rows (locked)"
fi
# the Google Chrome dock icon stays: its launcher is the first-run installer (pidesktop-chrome)
dconf update 2>/dev/null || true
log "default browser: $BR (xdg + alternatives); dock layout 10-pidesktop-shell"

# ---------------------------------------------------------------- music: Rhythmbox 3.5.1 (Plaid Claude's build, approved 2026-09-26)
# Newest upstream (Ubuntu has 3.4.9), all 13 meson features on, dark by default (one patch: prefer-dark-theme in
# impl_startup). One package that Conflicts/Replaces/Provides Ubuntu's split rhythmbox-* packages; held so an archive
# rhythmbox can't swap it for a build without those changes. Source record: userpatches/rhythmbox/ (build script +
# patch; the script fetches and sha256-checks the GNOME tarball). Codecs installed explicitly (the deb only Recommends
# them): libav = ALAC/AAC/APE/DSD/WMA, good = FLAC/WAV, bad = AIFF, ugly = MP3 extras.
# VLC is no longer in the image (user, 2026-09-26): Rhythmbox plays music, mpv stays the video player.
if ls "$OV"/debs/rhythmbox/rhythmbox_*.deb >/dev/null 2>&1; then
	apt-get install -y -qq --no-install-recommends "$OV"/debs/rhythmbox/rhythmbox_*.deb gstreamer1.0-libav \
		gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gvfs-backends >/dev/null \
		&& apt-mark hold rhythmbox >/dev/null && log "rhythmbox: $(dpkg-query -W -f='${Version}' rhythmbox) (held) + gstreamer codecs" \
		|| warn "rhythmbox install failed"
else
	warn "no rhythmbox deb in overlay/debs/rhythmbox — no music player in the image"
fi
# Armbian's desktop "mid" tier (armbian-configng desktops/yaml/common.yaml) installs vlc for every desktop. Pi-Desktop
# drops it (2026-09-26): Ubuntu's VLC 3.0.23 freezes the picture on Plaid with its default hardware decoding, and the
# old backport + software-decode override is gone. Purge exactly the installed vlc/libvlc packages (no autoremove).
VLCP=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'vlc*' 'libvlc*' 2>/dev/null | awk '$1 ~ /^[ih]i/ {print $2}')
if [[ -n $VLCP ]]; then
	apt-mark unhold $VLCP >/dev/null 2>&1
	apt-get purge -y -qq $VLCP >/dev/null && log "vlc: purged $(echo $VLCP | wc -w) packages that Armbian's desktop list installed" || warn "vlc purge failed"
fi
dpkg -s vlc >/dev/null 2>&1 && warn "vlc STILL installed after the purge"
# Disc burning: Brasero (GNOME's burner; pairs with Rhythmbox 3.5.1's brasero burn plugin) + cdrkit backends + cdrdao.
# Installed cleanly on the daily driver 2026-09-26 (8 pkgs incl. wodim/growisofs/genisoimage/libao). DVD playback is mpv
# (dvdnav/libbluray already in); libdvdcss is NOT shipped (DMCA) - users can build it with libdvd-pkg themselves.
apt-get install -y -qq --no-install-recommends brasero brasero-cdrkit cdrdao >/dev/null \
	&& log "burning: brasero $(dpkg-query -W -f='${Version}' brasero) + cdrkit + cdrdao" || warn "brasero install failed"

# ---------------------------------------------------------------- desktop extras
apt-get install -y -qq --no-install-recommends gnome-system-monitor iw fastfetch dconf-cli gnome-tweaks   # no zram-tools: Armbian zram-config already sets up /dev/zram0 swap; both at once = zramswap.service fails every boot >/dev/null 2>&1 || true
if [[ -x $OV/pro-updates/install-pro-updates.sh ]]; then
	( cd "$OV"/pro-updates && bash install-pro-updates.sh ) >/dev/null 2>&1 && log "pro-updates installed" || warn "pro-updates install failed"
fi

# ---------------------------------------------------------------- identity: Pi-Desktop, engine stays Ubuntu; Armbian cosmetics off, boot glue kept
# Armbian's base-files puts its own PRETTY_NAME in /etc/os-release (a regular file, not a symlink) -> the name keeper sets
# both files now and a DPkg::Post-Invoke hook re-applies it after any base-files upgrade from apt.armbian.com.
echo "${PDV}" > /etc/pi-desktop-release
install -m0755 "$OV"/usr/local/sbin/pidesktop-os-release /usr/local/sbin/pidesktop-os-release
install -Dm0644 "$OV"/etc/apt/apt.conf.d/99pidesktop-os-release /etc/apt/apt.conf.d/99pidesktop-os-release
/usr/local/sbin/pidesktop-os-release
grep -q "Pi-Desktop ${PDV}" /etc/os-release && log "os-release: $(grep PRETTY_NAME /etc/os-release)" || warn "PRETTY_NAME not applied to /etc/os-release"
echo pidesktop > /etc/hostname; sed -i "s/127.0.1.1.*/127.0.1.1\tpidesktop/" /etc/hosts
# "pidesktop" is only the pre-setup name: Armbian's first login never asks for a computer name, and two Pi-Desktops on one
# network would clash (mDNS, Samba). Ask right after the account is created, suggesting <username>-pidesktop (2026-09-26).
install -Dm0755 -o root -g root "$OV"/usr/local/sbin/pidesktop-set-hostname /usr/local/sbin/pidesktop-set-hostname
_fl=/usr/lib/armbian/armbian-firstlogin
if [[ -f $_fl ]] && ! grep -q pidesktop-set-hostname "$_fl"; then
	sed -i '/^\t# ask user to select automated locales or not$/i\
\t# Pi-Desktop: ask for the computer name (the image ships as "pidesktop"; two on one network would clash)\
\ttrap '"''"' 2\
\tPRESET_HOSTNAME="${PRESET_HOSTNAME:-}" /usr/local/sbin/pidesktop-set-hostname "${RealUserName:-}"\
\ttrap - INT\
' "$_fl"
fi
grep -q pidesktop-set-hostname "$_fl" 2>/dev/null && bash -n "$_fl" && log "first login: asks for the computer name" || warn "first login: computer-name step NOT inserted (armbian-firstlogin changed?)"
printf 'Pi-Desktop %s (Linux \\r) — \\l\n\n' "$PDV" > /etc/issue
apt-get purge -y -qq armbian-zsh armbian-config armbian-plymouth-theme 2>/dev/null || true   # keep armbian-bsp-cli-* (boot scripts, firstlogin) + armbian-firmware
for f in /etc/update-motd.d/*armbian*; do [[ -f $f ]] && chmod -x "$f"; done
# Privacy audit before the 4.0 release (2026-10-03): nothing in the image may phone home on its own.
#  - whoopsie, Ubuntu's crash-report UPLOADER, cannot be removed: gnome-control-center Depends on whoopsie-preferences,
#    which depends on whoopsie (apt refuses the purge against our held Settings package). So it is switched off twice:
#    both units masked (whoopsie.path watches /var/crash for *.upload files; nothing here ever creates one, since
#    apport-gtk is absent and automatic reporting is off) and report_crashes=false in /etc/default/whoopsie.
#    apport itself stays: it only writes local /var/crash files, useful for debugging, and never uploads by itself.
#  - armbian-quotes fetches a quote of the day from github.armbian.com by cron: the cron job goes.
#  Still contacting the network by design and disclosed in PRIVACY.md: apt (Ubuntu/Armbian/PPAs), unattended-upgrades,
#  GNOME Software update checks, fwupd's LVFS metadata refresh, chrony (Ubuntu's NTS pools), mDNS on the LAN, and the
#  first-login wizard's IP-based timezone/locale suggestion (Armbian's; on the list to replace).
if dpkg -s whoopsie >/dev/null 2>&1; then
	systemctl mask whoopsie.path whoopsie.service >/dev/null 2>&1 || true
	[[ -f /etc/default/whoopsie ]] && sed -i 's/^report_crashes=.*/report_crashes=false/' /etc/default/whoopsie
	grep -q '^report_crashes=' /etc/default/whoopsie 2>/dev/null || echo 'report_crashes=false' >> /etc/default/whoopsie
	if [[ $(readlink /etc/systemd/system/whoopsie.path) == /dev/null && $(readlink /etc/systemd/system/whoopsie.service) == /dev/null ]]; then
		log "privacy: whoopsie kept (Settings depends on it) but masked, report_crashes=false"
	else
		warn "privacy: whoopsie units NOT masked"
	fi
else
	log "privacy: whoopsie not installed"
fi
rm -f /etc/cron.d/armbian-quotes /etc/cron.daily/armbian-quotes 2>/dev/null
ls /etc/cron.d/armbian-quotes >/dev/null 2>&1 && warn "privacy: armbian-quotes cron still present" || log "privacy: armbian-quotes cron absent"
# Armbian's 20-ip-info curls ipv4.whatismyip.akamai.com at every login to print a WAN address: off, with the rest of the
# Armbian banner. Only our one-line 05-pi-desktop and the unattended-upgrades notice remain.
[[ -f /etc/default/armbian-motd ]] && sed -i 's/^MOTD_DISABLE=.*/MOTD_DISABLE="header ap-info ip-info containers-info sysinfo tips updates commands fwupd autoreboot-warn armbian-config"/' /etc/default/armbian-motd
# Canonical's IP policy (modified images must not carry Ubuntu's trademarks): the Ubuntu wallpaper and docs packages leave,
# the OS name is Pi-Desktop (pidesktop-os-release keeps NAME/PRETTY_NAME/LOGO/URLs; ID=ubuntu stays for apt/PPA tooling).
# ubuntu-wallpapers CANNOT go: Ubuntu's gnome-shell package depends on it. It stays installed and unused: its entries are
# hidden from Settings > Appearance (the chooser XMLs are diverted away) and the default wallpaper is ours.
safe_purge ubuntu-docs
safe_purge plymouth-theme-ubuntu-text || true
for x in /usr/share/gnome-background-properties/*ubuntu*.xml /usr/share/gnome-background-properties/*resolute*.xml; do
	[[ -f $x ]] && dpkg-divert --quiet --add --rename --divert "$x.pidesktop-hidden" "$x"
done
log "branding: Ubuntu wallpapers hidden from the chooser ($(ls /usr/share/gnome-background-properties/*.pidesktop-hidden 2>/dev/null | wc -l) lists diverted); ubuntu-docs $(dpkg -s ubuntu-docs >/dev/null 2>&1 && echo present || echo removed)"
# Pi-Desktop logo (branding/, CC BY-SA 4.0): Settings > About (LOGO=pi-desktop), the login screen and the boot screen. The boot
# theme derives from Ubuntu's spinner (plymouth's own GPL animation frames) with our watermark and fallback logo.
BR="$OV"/branding
if [[ -f $BR/pi-desktop.svg ]]; then
	install -Dm0644 -o root -g root "$BR"/pi-desktop.svg /usr/share/icons/hicolor/scalable/apps/pi-desktop.svg
	install -Dm0644 -o root -g root "$BR"/pi-desktop.svg /usr/share/pixmaps/pi-desktop.svg
	for s in 16 22 24 32 48 64 128 256 512; do
		[[ -f $BR/pi-desktop-$s.png ]] && install -Dm0644 -o root -g root "$BR/pi-desktop-$s.png" "/usr/share/icons/hicolor/${s}x${s}/apps/pi-desktop.png"
	done
	gtk-update-icon-cache -q -f /usr/share/icons/hicolor 2>/dev/null || true
	log "branding: pi-desktop icon ($(ls /usr/share/icons/hicolor/*/apps/pi-desktop.* | wc -l) sizes)"
else
	warn "branding: pi-desktop.svg missing — About keeps no logo"
fi
if [[ -f $BR/pi-desktop.plymouth && -f $BR/plymouth-bgrt-fallback.png && -d /usr/share/plymouth/themes/spinner ]]; then
	install -d /usr/share/plymouth/themes/pi-desktop
	cp -a /usr/share/plymouth/themes/spinner/*.png /usr/share/plymouth/themes/pi-desktop/ 2>/dev/null   # plymouth's own throbber/animation/dialog frames (GPL)
	rm -f /usr/share/plymouth/themes/pi-desktop/watermark.png            # Ubuntu's small corner logo: gone, and ours shows once, centred
	install -m0644 -o root -g root "$BR"/plymouth-bgrt-fallback.png /usr/share/plymouth/themes/pi-desktop/bgrt-fallback.png
	install -m0644 -o root -g root "$BR"/pi-desktop.plymouth /usr/share/plymouth/themes/pi-desktop/pi-desktop.plymouth
	update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth /usr/share/plymouth/themes/pi-desktop/pi-desktop.plymouth 200 >/dev/null 2>&1
	update-alternatives --set default.plymouth /usr/share/plymouth/themes/pi-desktop/pi-desktop.plymouth >/dev/null 2>&1
	# Armbian's image step does NOT rebuild the initrd here: it reuses a cached one unless the hash of a few paths changes
	# (/etc/initramfs-tools among them; lib/functions/image/initrd.sh). The 4.0 bake of 2026-10-03 shipped Ubuntu's bgrt
	# splash from that cache although the alternative pointed at ours. A marker that carries the theme's content hash lives
	# in a hashed path, so any change to the theme invalidates the cache and the plymouth hook packs the new theme.
	install -d /etc/initramfs-tools/conf.d
	printf '# Pi-Desktop boot theme: pi-desktop, content %s (cache key for the initrd; do not remove)\n' \
		"$(cat /usr/share/plymouth/themes/pi-desktop/pi-desktop.plymouth /usr/share/plymouth/themes/pi-desktop/bgrt-fallback.png | sha256sum | cut -c1-16)" \
		> /etc/initramfs-tools/conf.d/zz-pidesktop-theme
	update-initramfs -u -k all >/dev/null 2>&1 || true
	log "plymouth: pi-desktop theme = $(basename "$(readlink -f /etc/alternatives/default.plymouth)") (initrd cache key $(cut -d' ' -f6 /etc/initramfs-tools/conf.d/zz-pidesktop-theme))"
else
	warn "plymouth: pi-desktop theme assets missing — Ubuntu spinner stays"
fi
# licence summary inside the image (our code GPL-3.0-or-later, our art CC BY-SA 4.0, where the sources are)
install -Dm0644 -o root -g root "$OV"/usr/share/doc/pi-desktop/copyright /usr/share/doc/pi-desktop/copyright
cat > /etc/update-motd.d/05-pi-desktop <<-M
	#!/bin/sh
	printf '\\n  Pi-Desktop ${PDV}  ·  built from Ubuntu 26.04 packages  ·  GNOME 50  ·  kernel %s\\n\\n' "\$(uname -r)"
M
chmod +x /etc/update-motd.d/05-pi-desktop

# ---------------------------------------------------------------- defense-in-depth: 2.0.x modprobe blacklist (esp4/6, ipcomp, rds) — modules unused on a desktop
install -d /etc/modprobe.d && install -m0644 -o root -g root "$OV"/etc/modprobe.d/*.conf -t /etc/modprobe.d/ 2>/dev/null && log "modprobe.d: $(ls "$OV"/etc/modprobe.d/)"

# ---------------------------------------------------------------- boot args: CMA 512M (framework bootenv ships cma=256M; belt and braces with userpatches/bootenv)
# + FRL FLT_update polling off (kernel patch 0008): the older BSP never polled after FRL training and ran 4K@120 24/7 on
# the reference monitor; rkr7.2's 100 ms SCDC polling wedged the sink's DDC → black screens in 14 min–3 h. poll off:
# 2 h+ clean at 4K@120 incl. incident #3's load (2026-09-24). Only acts in FRL mode (>4K@60); TMDS modes never poll.
# + 4K@120 offered (test5 soak, 2026-09-25): kernel patch 0009 hides FRL modes unless rockchipdrm.allow_frl=1. With 0010
# (no FFE writes while the PHY is suspended: blank/wake hang) and 0011 (retrain after an HPD blip: black after a monitor
# power-cycle) every 120 Hz test passed on test4. Drop the arg from armbianEnv.txt to hide 120 Hz again, no rebuild.
for f in /boot/armbianEnv.txt /usr/share/armbian/armbianEnv.txt; do
	[[ -f $f ]] || continue
	sed -i 's/cma=256M/cma=512M/' "$f"
	grep -q '^extraargs=' "$f" || echo 'extraargs=' >> "$f"
	grep -q 'dw_hdmi_qp.frl_update_poll_ms=' "$f" || sed -i '/^extraargs=/ s/$/ dw_hdmi_qp.frl_update_poll_ms=0/' "$f"
	grep -q 'rockchipdrm.allow_frl=' "$f" || sed -i '/^extraargs=/ s/$/ rockchipdrm.allow_frl=1/' "$f"
	log "$f: $(grep ^extraargs "$f")"
done

# ---------------------------------------------------------------- hold our Armbian kernel/DT/boot/BSP/firmware packages
# The image enables apt.armbian.com. Our builds are 26.11.0-trunk and win over the repo today (newest there: 26.8.3), but
# Armbian's next release 26.11.1 sorts higher: Software Updater would swap in their stock rkr7.2 kernel + DTB and silently
# drop all our kernel patches (120 Hz fixes, WPA3 0006, AFBC, v0pll DT). Our kernel is updated by our own bakes instead.
for p in linux-image-vendor-rk35xx linux-dtb-vendor-rk35xx linux-headers-vendor-rk35xx linux-u-boot-orangepi5b-vendor \
	armbian-bsp-cli-orangepi5b-vendor armbian-firmware; do
	dpkg -s "$p" >/dev/null 2>&1 && apt-mark hold "$p" >/dev/null 2>&1
done
log "held Armbian packages: $(apt-mark showhold | grep -cE '^(linux-(image|dtb|headers|u-boot)|armbian-(bsp-cli|firmware))')/6"

# ---------------------------------------------------------------- analog audio: ES8388 3.5 mm jack was silent (OUT1 driver switch defaults off)
install -Dm0644 "$OV"/etc/systemd/system/pidesktop-es8388-out1.service /etc/systemd/system/pidesktop-es8388-out1.service
systemctl enable pidesktop-es8388-out1.service >/dev/null 2>&1 && log "analog audio: pidesktop-es8388-out1.service enabled (OUT1 Switch on at boot)" || warn "es8388 OUT1 service enable failed"
# jack and HDMI/DP are separate cards: follow the jack like a laptop (plug -> jack, unplug -> previous output)
install -Dm0755 "$OV"/usr/local/bin/pidesktop-headphone-follow /usr/local/bin/pidesktop-headphone-follow
install -Dm0644 "$OV"/etc/systemd/user/pidesktop-headphone-follow.service /etc/systemd/user/pidesktop-headphone-follow.service
systemctl --global enable pidesktop-headphone-follow.service >/dev/null 2>&1 && log "analog audio: headphone-follow user service enabled" || warn "headphone-follow enable failed"

# ---------------------------------------------------------------- Bluetooth: the two 2.0.x AP6275P fixes (CNX 2026-07-27) — NEVER drop these again
# Fix 2 (ubuntu-rockchip#2 / f432b71): Cypress BT/WiFi coex timing. This kernel is bcmdhd (CONFIG_BCMDHD=y) and downloads
# /lib/firmware/ap6275p/nvram_ap6275p.txt -> nvram_AP6275P.txt. NOT brcm/brcmfmac43752-pcie.txt (brcmfmac never loads here).
apt-get install -y -qq --no-install-recommends libnotify-bin >/dev/null 2>&1 || true   # bt-sentinel toasts
NVRAM=/lib/firmware/ap6275p/nvram_AP6275P.txt
if [[ -f $NVRAM ]]; then
	dpkg-divert --quiet --add --rename --divert "$NVRAM.armbian" "$NVRAM" && cp -a "$NVRAM.armbian" "$NVRAM"   # survive armbian-firmware upgrades
	grep -q '^btc_params8=' "$NVRAM" || printf '%s\n' '#BT Coex timing params (Pi Studio BT-3 mitigation, ubuntu-rockchip#2)' 'btc_params8=0x4e20' 'btc_params1=0x7530' 'btc_params50=0x972c' >> "$NVRAM"
	log "nvram: $(grep -c '^btc_params' "$NVRAM") btc_params lines in $NVRAM"
else
	warn "$NVRAM missing — AP6275P firmware layout changed; coex params NOT applied"
fi
# Fix 1 (ubuntu-rockchip#1 / 814a50f): boot race — unblock BT by type (never WiFi), power-cycle, attach, verify address, retry;
# plus the self-healing sentinel (bt-revive v4 restarts bluetooth-hciattach.service instead of driving patchram).
HA=/usr/local/sbin/bluetooth-hciattach.sh
if [[ -f $HA ]]; then
	dpkg-divert --quiet --add --rename --divert "$HA.armbian" "$HA"   # BSP package owns the original
	install -m0755 "$OV"/bt/bluetooth-hciattach.sh "$HA"
	install -m0755 "$OV"/bt/bt-revive "$OV"/bt/bt-sentinel /usr/local/sbin/
	install -m0644 "$OV"/bt/bt-sentinel.service /etc/systemd/system/bt-sentinel.service
	install -Dm0644 "$OV"/etc/systemd/system/bluetooth.service.d/10-pidesktop-wait-hci0.conf /etc/systemd/system/bluetooth.service.d/10-pidesktop-wait-hci0.conf
	install -Dm0644 "$OV"/etc/udev/rules.d/99-pidesktop-bt-unblock.rules /etc/udev/rules.d/99-pidesktop-bt-unblock.rules
	systemctl enable bt-sentinel.service >/dev/null 2>&1
	sed -i 's/^#\?AutoEnable=.*/AutoEnable=true/' /etc/bluetooth/main.conf 2>/dev/null || true
	log "bluetooth: hardened hciattach + bt-sentinel installed"
else
	warn "$HA missing — Armbian bluetooth-hciattach extension not active for this board; BT boot-race fix NOT applied"
fi

# ---------------------------------------------------------------- test1 fixes Pi Claude archived that were never baked (audit 2026-09-24)
# (1) codec service + 2D engine are root-only on an Armbian rootfs -> hardware video impossible for the desktop user
install -Dm0644 "$OV"/etc/udev/rules.d/99-pidesktop-rockchip-codec.rules /etc/udev/rules.d/99-pidesktop-rockchip-codec.rules
# (2) bluez mpris-proxy relays browser media-session state to AVRCP; the WiiM mutes ~10 s on each STOPPED (every YouTube ad)
systemctl --global disable mpris-proxy.service >/dev/null 2>&1 || true
install -Dm0644 "$OV"/etc/systemd/user-preset/90-pidesktop-no-mpris-proxy.preset /etc/systemd/user-preset/90-pidesktop-no-mpris-proxy.preset
# (3) *.local names: libnss-mdns is installed but not in nsswitch; gvfs-fuse + cifs-utils for NAS shares from Files
sed -i 's/^hosts:.*/hosts:          files mymachines mdns4_minimal [NOTFOUND=return] dns myhostname/' /etc/nsswitch.conf
apt-get install -y -qq --no-install-recommends libnss-mdns gvfs-fuse cifs-utils >/dev/null 2>&1 || warn "mdns/gvfs-fuse/cifs install failed"
# (4) no root password logins over SSH
install -Dm0644 "$OV"/etc/ssh/sshd_config.d/10-pidesktop.conf /etc/ssh/sshd_config.d/10-pidesktop.conf
# (5) Firefox's neutral policy file (no Armbian homepage/bookmarks, telemetry off) now travels with the Firefox installer
#     (pidesktop-install-app firefox diverts any distro policy and installs ours).
# (6) Plaid terminal greeting: fastfetch with the tartan pi logo on interactive shells
apt-get install -y -qq --no-install-recommends fastfetch >/dev/null 2>&1 || true
install -Dm0644 "$OV"/fastfetch/plaid.ans /usr/share/pi-desktop/fastfetch/plaid.ans
install -Dm0644 "$OV"/fastfetch/config.jsonc /etc/fastfetch/config.jsonc
grep -q PI_DESKTOP_FETCHED /etc/bash.bashrc || cat "$OV"/fastfetch/bash.bashrc.snippet >> /etc/bash.bashrc
log "test1 fixes: codec udev, mpris-proxy off, mdns+gvfs-fuse+cifs, root ssh key-only, plaid fastfetch"

# ---------------------------------------------------------------- persistent journal (hang/crash evidence survives the reboot; 200 MB cap)
install -Dm0644 "$OV"/etc/systemd/journald.conf.d/10-pidesktop-persistent.conf /etc/systemd/journald.conf.d/10-pidesktop-persistent.conf
install -d -m2755 -g systemd-journal /var/log/journal 2>/dev/null || install -d /var/log/journal
log "journald: persistent (200 MB)"

# ---------------------------------------------------------------- manifest for Pi Claude
{
	echo "Pi-Desktop ${PDV} — built $(date -u +%F' '%T) UTC — BOARD=$BOARD RELEASE=$RELEASE FAMILY=$LINUXFAMILY GPU=$GPU"
	echo; echo "## key packages"
	dpkg-query -W -f='${Package} ${Version}\n' 'linux-image-*' 'linux-dtb-*' 'linux-u-boot-*' gnome-shell mutter gdm3 mesa-vulkan-drivers libegl-mesa0 'libmali-*' \
		pipewire wireplumber librockchip-mpp1 librockchip-mpp-dev librockchip-vpu1 librga2 rockchip-vaapi libva2 mpv ffmpeg chromium firefox linux-firmware bluez alsa-ucm-conf 2>/dev/null | sort
	echo; echo "## held"; apt-mark showhold
	echo; echo "## pulseaudio present?"; dpkg -l 'pulseaudio*' 2>/dev/null | grep '^ii' || echo none
} > /etc/pi-desktop-manifest.txt
log "manifest: /etc/pi-desktop-manifest.txt"; cat /etc/pi-desktop-manifest.txt
apt-get clean
# Armbian's post-customize hooks (armbian-config install) pre-flight-check that /var/lib/apt/lists is empty;
# our apt-get update above filled it. Empty it (first boot's apt update regenerates it).
find /var/lib/apt/lists -type f ! -name lock -delete 2>/dev/null
find /var/cache/apt -type f -delete 2>/dev/null   # framework pre-flights tolerate at most 1 file here too
exit 0


# ---------------------------------------------------------------- final guard: a desktop image must still contain its desktop
MISSING=""
for p in gnome-shell gdm3 mutter gnome-session-bin gnome-control-center nautilus chromium pipewire wireplumber fonts-adwaita; do
	dpkg -s "$p" >/dev/null 2>&1 || MISSING="$MISSING $p"
done
if [[ -n $MISSING ]]; then
	warn "CRITICAL: core desktop packages missing:$MISSING — refusing to finish this image"
	exit 1
fi
log "final guard: core desktop packages present"
