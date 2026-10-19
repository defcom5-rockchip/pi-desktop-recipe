#!/bin/bash
# Fetch an Ubuntu 26.04 ("resolute") source package and verify it through the archive chain:
# InRelease (Ubuntu archive key) -> Sources.xz (hash in InRelease) -> every source file (SHA256 in Sources.xz). No root.
# Usage: fetch-ubuntu-source.sh SRC VERSION OUTDIR
set -euo pipefail
SRC=$1; VER=$2; OUT=$3; ARCHIVE=https://ports.ubuntu.com/ubuntu-ports; KEYRING=/usr/share/keyrings/ubuntu-archive-keyring.gpg
mkdir -p "$OUT/index"; cd "$OUT/index"; want=""
for pocket in resolute-security resolute-updates resolute; do
  curl -fsS -o "InRelease-$pocket" "$ARCHIVE/dists/$pocket/InRelease"
  gpgv --keyring "$KEYRING" --output "Release-$pocket" "InRelease-$pocket" 2>/dev/null || { echo "E: bad signature on $pocket"; exit 1; }
  for comp in main universe; do
    f="Sources-$pocket-$comp.xz"; curl -fsS -o "$f" "$ARCHIVE/dists/$pocket/$comp/source/Sources.xz" || continue
    h=$(awk -v p="$comp/source/Sources.xz" '/^SHA256:/{s=1;next} /^[^ ]/{s=0} s && $3==p{print $1}' "Release-$pocket")
    [ "$(sha256sum < "$f" | cut -d' ' -f1)" = "$h" ] || { echo "E: $f hash mismatch"; exit 1; }
    ent=$(xz -dc "$f" | awk -v RS= -v s="$SRC" -v v="$VER" 'index($0, "Package: " s "\n")==1 && index($0, "\nVersion: " v "\n")')
    if [ -n "$ent" ]; then want=$(printf '%s\n' "$ent" | awk '/^Checksums-Sha256:/{f=1;next} /^[^ ]/{f=0} f{print $1, $3}')
      dir=$(printf '%s\n' "$ent" | awk '/^Directory:/{print $2}'); echo "index: $SRC $VER in $pocket/$comp (signature + hashes OK)"; break 2; fi
  done
done
[ -n "$want" ] || { echo "E: $SRC $VER not found"; exit 1; }
cd "$OUT"; while read -r sum name; do
  if [ -f "$name" ] && echo "$sum  $name" | sha256sum -c --status -; then continue; fi
  curl -fsS -o "$name" "$ARCHIVE/$dir/$name"; echo "$sum  $name" | sha256sum -c --quiet - || { echo "E: $name hash mismatch"; exit 1; }
done <<< "$want"
echo "source: $(echo "$want" | wc -l) files verified in $OUT"
