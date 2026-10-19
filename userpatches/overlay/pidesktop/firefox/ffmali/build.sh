#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 defcom5-rockchip
# build.sh — build libpidesktop-ffmali.so.1 (the Firefox-only Mali fix-up library) next to this script.
#   bash build.sh                      on an x86-64 build host: cross-compiles with aarch64-linux-gnu-gcc against the
#                                      Mali package the image installs (recipe inputs/libmali-valhall-g610-*.deb, or
#                                      MALI_DEB=/path/to/that.deb)
#   bash build.sh --native             on an arm64 board with libmali installed: links the installed libraries
# The result is installed by customize-image.sh into /usr/local/lib/pidesktop-firefox-mali/ (see the README).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/libpidesktop-ffmali.c
OUT=$HERE/libpidesktop-ffmali.so.1
FLAGS=(-O2 -fPIC -shared -Wall -Wextra -Wno-unused-parameter -Wl,-soname,libpidesktop-ffmali.so.1
       -Wl,-Bsymbolic-functions -Wl,-z,relro,-z,now)
if [[ ${1:-} == --native ]]; then
	L=/usr/lib/aarch64-linux-gnu
	gcc "${FLAGS[@]}" -o "$OUT" "$SRC" -Wl,--no-as-needed "$L/libmali-hook.so.1" "$L/libmali.so.1" -lpthread -ldl
else
	DEB=${MALI_DEB:-$(ls "$HERE"/../../debs/libmali-valhall-g610-*-wayland-gbm_*_arm64.deb \
	                    "$HERE"/../../../../../inputs/libmali-valhall-g610-*-wayland-gbm_*_arm64.deb 2>/dev/null | head -1 || true)}
	[[ -n $DEB && -f $DEB ]] || { echo "E: libmali .deb not found (recipe inputs/, or set MALI_DEB=)" >&2; exit 1; }
	T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
	dpkg-deb -x "$DEB" "$T"
	L=$T/usr/lib/aarch64-linux-gnu
	aarch64-linux-gnu-gcc "${FLAGS[@]}" -o "$OUT" "$SRC" -Wl,--no-as-needed "$L/libmali-hook.so.1" "$L/libmali.so.1" \
		-Wl,--allow-shlib-undefined -lpthread -ldl
	echo "linked against $(basename "$DEB")"
fi
sha256sum "$OUT"
