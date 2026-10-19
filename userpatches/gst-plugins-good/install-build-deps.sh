#!/bin/bash
# Install the build dependencies of Ubuntu's gst-plugins-good1.0 straight from the downloaded .dsc (no deb-src needed).
# Simulates first and refuses if anything would be REMOVED.   Run:  sudo bash install-build-deps.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }
U="${SUDO_USER:-$(id -nu "${PKEXEC_UID:-0}")}"; UH=$(getent passwd "$U" | cut -d: -f6)
DSC=$(ls "$UH"/Development/gstreamer/work/src/gst-plugins-good1.0_*.dsc 2>/dev/null | tail -1)
[ -n "$DSC" ] || { echo "E: no .dsc yet: run build-gst-plugins-good-deb.sh --prepare-only as $U first"; exit 1; }
echo "== build deps of $(basename "$DSC") (simulated)"
SIM=$(apt-get build-dep -s "$DSC" 2>&1) || { echo "$SIM" | tail -15; echo "E: apt cannot satisfy them (held package?)"; exit 1; }
echo "$SIM" | grep -E '^(Inst|Remv) ' | awk '{print $1}' | sort | uniq -c
if echo "$SIM" | grep -q '^Remv '; then echo "E: this would REMOVE:"; echo "$SIM" | grep '^Remv '; exit 1; fi
apt-get build-dep -y "$DSC"
echo "Done. Now, as $U:  bash $(dirname "$0")/build-gst-plugins-good-deb.sh"
