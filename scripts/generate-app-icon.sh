#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_SVG="$ROOT_DIR/Resources/AppIcon.svg"
SOURCE_PNG="$ROOT_DIR/Resources/AppIcon.png"
ICONSET_DIR="$ROOT_DIR/Resources/AppIcon.iconset"
OUTPUT_ICNS="$ROOT_DIR/Resources/AppIcon.icns"

if ! command -v rsvg-convert >/dev/null 2>&1; then
    echo "error: rsvg-convert is required to render $SOURCE_SVG" >&2
    exit 1
fi
if ! command -v sips >/dev/null 2>&1; then
    echo "error: sips is required to resize icon PNGs" >&2
    exit 1
fi
if ! command -v iconutil >/dev/null 2>&1; then
    echo "error: iconutil is required to create $OUTPUT_ICNS" >&2
    exit 1
fi

rsvg-convert -w 1024 -h 1024 "$SOURCE_SVG" -o "$SOURCE_PNG"

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

sips -z 16 16 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$SOURCE_PNG" "$ICONSET_DIR/icon_512x512@2x.png"

rm -f "$OUTPUT_ICNS"
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"
rm -rf "$ICONSET_DIR"

echo "Generated $SOURCE_PNG"
echo "Generated $OUTPUT_ICNS"
