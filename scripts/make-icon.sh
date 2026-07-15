#!/bin/bash
# Renders the icon (make-icon.swift) and packages it as AppIcon.icns at the repo root.
set -euo pipefail
cd "$(dirname "$0")/.."

TMP=$(mktemp -d)
swift scripts/make-icon.swift "$TMP/icon_1024.png"

ICONSET="$TMP/AppIcon.iconset"
mkdir "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" > /dev/null
    d=$((s * 2))
    sips -z $d $d "$TMP/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" > /dev/null
done

iconutil -c icns "$ICONSET" -o AppIcon.icns

# PNG for the README / GitHub.
mkdir -p assets
sips -z 256 256 "$TMP/icon_1024.png" --out assets/icon.png > /dev/null

rm -rf "$TMP"
echo "Built AppIcon.icns and assets/icon.png"
