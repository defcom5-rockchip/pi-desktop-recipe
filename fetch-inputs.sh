#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 defcom5-rockchip (Pi-Desktop)
#
# fetch-inputs.sh — put the binary build inputs in place under userpatches/ and verify them.
#
# The recipe installs a number of pre-built files that are too large (or not source) for git: the rebuilt
# .deb packages under overlay/pidesktop/debs/, the ARM Mali userspace driver package, the patched libmali
# hook library and the screensaver video. They are attached to a GitHub release instead. This script
# downloads each one into the path the recipe expects and checks it against userpatches/INPUTS.sha256.
#
#   ./fetch-inputs.sh                       download from the GitHub release (default URL below)
#   INPUTS_URL=<base url> ./fetch-inputs.sh  any other base URL, e.g. file:///path/to/a/local/inputs/dir
#
# Fail-closed: a file whose checksum does not match is never left in place (it is moved aside as
# <name>.mismatch, which the recipe's globs do not pick up) and the script exits non-zero. Files that are
# already present and correct are skipped, so re-running is cheap.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
UP="$HERE/userpatches"
SUMS="$UP/INPUTS.sha256"
BASE="${INPUTS_URL:-https://github.com/defcom5-rockchip/pi-desktop-recipe/releases/download/inputs-4.0}"
BASE="${BASE%/}"

for t in curl sha256sum; do
	command -v "$t" >/dev/null 2>&1 || { echo "E: $t is required" >&2; exit 1; }
done
[[ -f $SUMS ]] || { echo "E: $SUMS is missing — run this from a checkout of the recipe" >&2; exit 1; }

sha() { sha256sum "$1" | cut -d' ' -f1; }

present=0 fetched=0 failed=0
while read -r want rel; do
	[[ -z ${want:-} || ${want:0:1} == '#' ]] && continue
	dst="$UP/$rel"
	name="${rel##*/}"
	if [[ -f $dst ]]; then
		if [[ $(sha "$dst") == "$want" ]]; then
			echo "ok      $rel"
			present=$((present + 1))
			continue
		fi
		echo "stale   $rel (checksum differs — moving aside as $name.mismatch and downloading again)"
		mv -f "$dst" "$dst.mismatch"
	fi
	mkdir -p "${dst%/*}"
	tmp="$dst.part"
	rm -f "$tmp"
	echo "fetch   $name"
	if ! curl -fsSL --retry 3 --retry-delay 2 --proto '=https,file' -o "$tmp" "$BASE/$name"; then
		echo "E: download failed: $BASE/$name" >&2
		rm -f "$tmp"
		failed=$((failed + 1))
		continue
	fi
	got=$(sha "$tmp")
	if [[ $got != "$want" ]]; then
		echo "E: checksum mismatch for $rel" >&2
		echo "   expected $want" >&2
		echo "   got      $got" >&2
		rm -f "$tmp"
		failed=$((failed + 1))
		continue
	fi
	mv -f "$tmp" "$dst"
	chmod 0644 "$dst"
	echo "ok      $rel (downloaded)"
	fetched=$((fetched + 1))
done < "$SUMS"

echo
echo "inputs: $present already present, $fetched downloaded, $failed failed"
if [[ $failed -gt 0 ]]; then
	echo "E: $failed input(s) missing or wrong — do not build until this passes" >&2
	exit 1
fi
echo "all inputs verified against $SUMS"
