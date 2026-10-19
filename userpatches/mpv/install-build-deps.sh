#!/bin/bash
# Build dependencies for Ubuntu's mpv 0.41.0 rebuilt for Pi-Desktop (build-mpv-deb.sh): its Build-Depends minus
# libpipewire-0.3-dev (Ubuntu's headers conflict with the held PipeWire 1.6.9~pd31; the build uses -Dpipewire=disabled and
# plays through pipewire-pulse). libjack-dev -> libjack-jackd2-dev (keeps JACK2). Simulates first, refuses removals.
# Run: sudo bash install-build-deps.sh [WORKDIR]     (WORKDIR as given to build-mpv-deb.sh; it fetches the .dsc first)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }
U="${SUDO_USER:-$(id -nu "${PKEXEC_UID:-0}")}"; UH=$(getent passwd "$U" | cut -d: -f6)
W="${1:-$UH/Development/mpv/ubuntu-pd}"
DSC=$(ls "$W"/src-pkg/mpv_*.dsc 2>/dev/null | tail -1); [ -n "$DSC" ] || { echo "E: no Ubuntu mpv .dsc in $W/src-pkg (run build-mpv-deb.sh $W --prepare-only first)"; exit 1; }
mapfile -t DEPS < <(python3 - "$DSC" <<'PY'
import re, sys
txt = open(sys.argv[1]).read()
m = re.search(r'^Build-Depends:(.*?)(?=^\S)', txt, re.S | re.M)
for dep in m.group(1).replace('\n', ' ').split(','):
    alt = dep.split('|')[0].strip()
    if not alt: continue
    arch = re.search(r'\[([^\]]+)\]', alt)
    if arch and not any(a in ('linux-any', 'any', 'arm64') or (a.startswith('!') and a[1:] not in ('arm64', 'linux-any')) for a in arch.group(1).split()):
        continue
    name = re.sub(r'\s*[\(\[<].*$', '', alt).strip()
    # libjack-dev is a virtual name here: apt would pick JACK1 and remove the installed JACK2 runtime
    # (mpv, libavdevice, pipewire's JACK bridge depend on it); JACK2's -dev provides the same headers.
    name = {'libjack-dev': 'libjack-jackd2-dev'}.get(name, name)
    if name and name != 'libpipewire-0.3-dev':
        print(name)
PY
)
DEPS+=(meson ninja-build pkg-config)
echo "== ${#DEPS[@]} build deps (simulated):"
SIM=$(apt-get install -s --no-install-recommends "${DEPS[@]}" 2>&1) || { echo "$SIM" | tail -12; exit 1; }
echo "$SIM" | grep -E '^(Inst|Remv) ' | awk '{print $1}' | sort | uniq -c
if echo "$SIM" | grep -q '^Remv '; then echo "E: would REMOVE:"; echo "$SIM" | grep '^Remv '; exit 1; fi
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${DEPS[@]}" | grep -cE '^Setting up' | sed 's/^/packages set up: /'
