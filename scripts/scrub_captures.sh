#!/usr/bin/env bash
set -e
SRC=raw; DST=scrubbed; mkdir -p "$DST"

for f in "$SRC"/*; do
  b=$(basename "$f")
  sed -E \
    -e 's/Hostname="[0-9a-f]{12}"/Hostname="node-000"/g' \
    -e 's/\b[0-9a-f]{64}\b/CONTAINERIDLONG/g' \
    -e 's/(^|[^-0-9a-f])[0-9a-f]{12}([^-0-9a-f]|$)/\1CONTAINERID00\2/g' \
    -e 's/GPU-[0-9a-fA-F-]{8}-[0-9a-zA-Z-]*/GPU-00000000-0000-0000-0000-000000000000/g' \
    -e 's/"serial_num" : "[0-9]+"/"serial_num" : "0000000000000"/g' \
    -e 's/(Serial Number[[:space:]]*:[[:space:]]*)[0-9]+/\10000000000000/g' \
    -e 's/1322921055680/0000000000000/g' \
    -e 's/saransh23b0121091/gfuser/g' \
    -e 's/132-145-137-30/node-000/g' \
    -e 's/UUID=[0-9a-f]{8}-[0-9a-f-]{27}/UUID=00000000-0000-0000-0000-000000000000/g' \
    -e 's#/teamspace/studios/this_studio#/home/gfuser#g' \
    "$f" > "$DST/$b"
done
echo "scrubbed $(ls -1 $DST | wc -l) files"
