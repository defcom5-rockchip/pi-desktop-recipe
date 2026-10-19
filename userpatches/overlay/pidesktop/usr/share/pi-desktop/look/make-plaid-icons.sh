#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 defcom5-rockchip (Pi-Desktop). The icons it produces follow Adwaita's licence (see COPYING in the theme).
# Build the "Plaid" icon theme: Adwaita, with the folder family recoloured (peach body, logo-blue tab). Default target is
# per-user; the image ships the result in /usr/share/icons/Plaid (pass that path as $1 to regenerate it there, as root).
# Run: bash make-plaid-icons.sh   then: gsettings set org.gnome.desktop.interface icon-theme 'Plaid'
set -euo pipefail
T=${1:-$HOME/.local/share/icons/Plaid}; A=/usr/share/icons/Adwaita; mkdir -p "$T/scalable/places" "$T/16x16/places"
cat > "$T/index.theme" <<'IDX'
[Icon Theme]
Name=Plaid
Comment=Adwaita with Pi-Desktop Plaid folders: peach body, navy-blue tab (CC BY-SA 3.0 US or LGPL-3.0, see COPYING)
Inherits=Adwaita,AdwaitaLegacy,hicolor
Directories=16x16/places,scalable/places

[16x16/places]
Size=16
Context=Places
Type=Fixed

[scalable/places]
Size=128
MinSize=8
MaxSize=512
Context=Places
Type=Scalable
IDX
# Adwaita blue -> Plaid: tab/emblems #438de6 -> logo blue #21418c; body #62a0ea -> peach #e9a67c; highlights -> lighter peach
MAP='s/#438de6/#21418c/gI; s/#62a0ea/#e9a67c/gI; s/#afd4ff/#f8d8bc/gI; s/#c0d5ea/#f6d0b0/gI; s/#a4caee/#f3c7a2/gI'
for f in "$A"/scalable/places/folder*.svg "$A"/scalable/places/user-home.svg "$A"/scalable/places/user-desktop.svg; do sed "$MAP" "$f" > "$T/scalable/places/$(basename "$f")"; done
python3 - "$T" <<'PY'
import gi, os, glob, sys, cairo; gi.require_version('Rsvg','2.0'); from gi.repository import Rsvg
T=sys.argv[1]
for svg in glob.glob(f'{T}/scalable/places/*.svg'):
    h=Rsvg.Handle.new_from_file(svg); d=h.get_dimensions(); s=cairo.ImageSurface(cairo.FORMAT_ARGB32,16,16); c=cairo.Context(s)
    c.scale(16/d.width,16/d.height); h.render_cairo(c); s.write_to_png(f'{T}/16x16/places/{os.path.basename(svg)[:-4]}.png')
PY
# the licence travels with the icons (the image ships the same COPYING)
[ -f /usr/share/icons/Plaid/COPYING ] && [ "$T" != /usr/share/icons/Plaid ] && cp /usr/share/icons/Plaid/COPYING "$T/"
gtk-update-icon-cache -q -f "$T" 2>/dev/null || true
echo "Plaid icon theme at $T ($(ls "$T/scalable/places" | wc -l) folder icons). Needs: python3-gi gir1.2-rsvg-2.0 python3-cairo."
