#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="$ROOT_DIR/Xcode/Info.plist"
DIST_DIR="$ROOT_DIR/dist"
APPCAST_PATH="$ROOT_DIR/appcast.xml"
APP_NAME="ZCodeAccountSwitcher"
SPARKLE_KEY_ACCOUNT="zcode-account-switcher"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
DMG_PATH="${1:-$DIST_DIR/$APP_NAME-$VERSION-macOS.dmg}"
DMG_NAME="$(basename "$DMG_PATH")"
RELEASE_URL="https://github.com/FedyaLight/zcode-account-switcher/releases/download/v$VERSION/$DMG_NAME"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG not found: $DMG_PATH" >&2
  exit 1
fi

SIGN_UPDATE="$(find "$ROOT_DIR/.build/artifacts/sparkle" -path "*/bin/sign_update" -type f | head -n 1 || true)"
if [[ -z "$SIGN_UPDATE" ]]; then
  echo "Sparkle sign_update was not found. Run swift package resolve first." >&2
  exit 1
fi

sign_args=(--account "$SPARKLE_KEY_ACCOUNT")
if [[ -n "${SPARKLE_ED_KEY_FILE:-}" ]]; then
  sign_args=(--ed-key-file "$SPARKLE_ED_KEY_FILE")
fi

SIGNATURE="$("$SIGN_UPDATE" "${sign_args[@]}" "$DMG_PATH" | awk -F 'edSignature="' '{print $2}' | awk -F '"' '{print $1}')"
if [[ -z "$SIGNATURE" ]]; then
  echo "Could not extract Sparkle signature for $DMG_PATH" >&2
  exit 1
fi

LENGTH="$(stat -f %z "$DMG_PATH")"
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

cat > "$APPCAST_PATH" <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>ZCode Account Switcher Updates</title>
    <link>https://github.com/FedyaLight/zcode-account-switcher/releases</link>
    <description>Release feed for ZCode Account Switcher.</description>
    <language>en</language>
    <item>
      <title>Version $VERSION</title>
      <sparkle:releaseNotesLink>https://github.com/FedyaLight/zcode-account-switcher/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <pubDate>$PUB_DATE</pubDate>
      <enclosure
        url="$RELEASE_URL"
        sparkle:version="$BUILD"
        sparkle:shortVersionString="$VERSION"
        sparkle:edSignature="$SIGNATURE"
        length="$LENGTH"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
APPCAST

echo "Wrote $APPCAST_PATH"
