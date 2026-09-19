#!/usr/bin/env bash
# Scrub capture artifacts for public commit.
# Idempotent. Format-preserving. Single source of truth for
# data/captures/raw/ -> data/captures/scrubbed/
#
# NOTE: scrubbing is deliberately NARROW. Telemetry values
# (throttle bitmasks, memory maps, counters) must survive
# untouched - they are the reason the captures exist.
set -euo pipefail

SRC="${1:-data/captures/raw}"
DST="${2:-data/captures/scrubbed}"
PREFIX="${3:-}"          # e.g. "modal_" for session-2 artifacts

mkdir -p "$DST"

for f in "$SRC"/*; do
  [ -f "$f" ] || continue
  b="$PREFIX$(basename "$f")"
  sed -E \
    -e 's/(comm|connection|pointer|dlHandle) 0x[0-9a-f]+/\1 0xADDR/g' \
    -e 's/commId 0x[0-9a-f]+/commId 0xCOMMID/g' \
    -e 's/Hostname="[0-9a-f]{12}"/Hostname="node-000"/g' \
    -e 's/\b[0-9a-f]{64}\b/CONTAINERIDLONG/g' \
    -e 's/(^|[^-0-9a-f])[0-9a-f]{12}([^-0-9a-f]|$)/\1CONTAINERID00\2/g' \
    -e 's/GPU-[0-9a-fA-F-]{8}-[0-9a-zA-Z-]*/GPU-00000000-0000-0000-0000-000000000000/g' \
    -e 's/"serial_num" : "[0-9]+"/"serial_num" : "0000000000000"/g' \
    -e 's/(Serial Number[[:space:]]*:[[:space:]]*)[0-9]+/\10000000000000/g' \
    -e 's/172\.[0-9]+\.[0-9]+\.[0-9]+/10.0.0.1/g' \
    -e 's/\b[0-9]{1,3}-[0-9]{1,3}-[0-9]{1,3}-[0-9]{1,3}\b/node-000/g' \
    -e 's/UUID=[0-9a-f]{8}-[0-9a-f-]{27}/UUID=00000000-0000-0000-0000-000000000000/g' \
    -e 's#/teamspace/studios/this_studio#/home/gfuser#g' \
    -e 's/\b[a-z]+[0-9]{2}b[0-9]{10}\b/gfuser/g' \
    "$f" > "$DST/$b"
done

echo "scrubbed $(ls -1 "$DST" | wc -l) files into $DST"
