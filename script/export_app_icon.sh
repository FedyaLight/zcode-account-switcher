#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_DOC="$ROOT_DIR/Resources/AppIcon.icon"
ICON_JSON="$ICON_DOC/icon.json"
PNG_OUT="$ROOT_DIR/Resources/ZCodeAccountSwitcher.png"
ICNS_OUT="$ROOT_DIR/Resources/ZCodeAccountSwitcher.icns"
SOURCE_GENERATOR="$ROOT_DIR/script/generate_app_icon_source.swift"

ICON_TOOL="/Applications/Xcode-beta.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
if [[ ! -x "$ICON_TOOL" ]]; then
  ICON_TOOL="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
fi

if [[ ! -x "$ICON_TOOL" ]]; then
  echo "Icon Composer ictool was not found." >&2
  exit 1
fi

if [[ -f "$SOURCE_GENERATOR" ]]; then
  /usr/bin/swift "$SOURCE_GENERATOR" "$ROOT_DIR/Resources/AppIcon.icon/Assets/icon-source.png"
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
iconset="$tmpdir/AppIcon.iconset"
mkdir -p "$iconset"

"$ICON_TOOL" "$ICON_DOC" \
  --export-image \
  --output-file "$PNG_OUT" \
  --platform macOS \
  --rendition Default \
  --width 1024 \
  --height 1024 \
  --scale 1

make_icon() {
  local size="$1"
  local name="$2"
  /usr/bin/sips -s format png -z "$size" "$size" "$PNG_OUT" --out "$iconset/$name" >/dev/null
}

make_icon 16 "icon_16x16.png"
make_icon 32 "icon_16x16@2x.png"
make_icon 32 "icon_32x32.png"
make_icon 64 "icon_32x32@2x.png"
make_icon 128 "icon_128x128.png"
make_icon 256 "icon_128x128@2x.png"
make_icon 256 "icon_256x256.png"
make_icon 512 "icon_256x256@2x.png"
make_icon 512 "icon_512x512.png"
make_icon 1024 "icon_512x512@2x.png"

/usr/bin/iconutil -c icns "$iconset" -o "$ICNS_OUT"
