#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ZCodeAccountSwitcher"
DISPLAY_NAME="ZCode Account Switcher"
BUNDLE_ID="com.zcode.account-switcher.mac"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_TEMPLATE="$ROOT_DIR/Xcode/Info.plist"
APP_ICON="$ROOT_DIR/Resources/ZCodeAccountSwitcher.icns"
DIST_DIR="$ROOT_DIR/dist"
PACKAGE_DIR="$ROOT_DIR/.build/release-package"
APP_BUNDLE="$PACKAGE_DIR/$DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_TEMPLATE")"
DMG_BASENAME="$APP_NAME-$VERSION-macOS"
DMG_PATH="$DIST_DIR/$DMG_BASENAME.dmg"
SHA_PATH="$DMG_PATH.sha256"
RW_DMG_PATH="$PACKAGE_DIR/$DMG_BASENAME-rw.dmg"

rm -rf "$PACKAGE_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$DIST_DIR"

swift build -c release
BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

cp "$BUILD_BINARY" "$APP_BINARY"
cp "$APP_ICON" "$APP_RESOURCES/ZCodeAccountSwitcher.icns"
cp "$INFO_TEMPLATE" "$APP_CONTENTS/Info.plist"
chmod +x "$APP_BINARY"

/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $MIN_SYSTEM_VERSION" "$APP_CONTENTS/Info.plist"

codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

HELPER_NAME="Run to Remove Quarantine.command"
HELPER_SCRIPT="$PACKAGE_DIR/$HELPER_NAME"
cat > "$HELPER_SCRIPT" <<'HELPER'
#!/bin/zsh
set -euo pipefail

app_path="/Applications/ZCode Account Switcher.app"

if [[ ! -d "$app_path" ]]; then
  /usr/bin/osascript -e 'display alert "ZCode Account Switcher is not installed" message "Drag the app to Applications first, then run this helper again." as warning'
  exit 1
fi

/usr/bin/xattr -dr com.apple.quarantine "$app_path" 2>/dev/null || true
/usr/bin/open "$app_path"
HELPER
chmod +x "$HELPER_SCRIPT"

rm -f "$DMG_PATH" "$SHA_PATH" "$RW_DMG_PATH"
hdiutil create \
  -size 80m \
  -volname "$DISPLAY_NAME" \
  -fs "HFS+" \
  -ov \
  "$RW_DMG_PATH"

device="$(hdiutil attach "$RW_DMG_PATH" -readwrite -noverify -noautoopen | awk '/Apple_HFS|Apple_APFS/ { print $1 }' | tail -n 1)"
mount_point="/Volumes/$DISPLAY_NAME"

cleanup_mount() {
  if [[ -n "${device:-}" ]]; then
    hdiutil detach "$device" >/dev/null 2>&1 || true
  fi
}
trap cleanup_mount EXIT

ditto "$APP_BUNDLE" "$mount_point/$DISPLAY_NAME.app"
ln -s /Applications "$mount_point/Applications"
cp "$HELPER_SCRIPT" "$mount_point/$HELPER_NAME"
chmod +x "$mount_point/$HELPER_NAME"

if [[ "${ZCAS_SKIP_DMG_LAYOUT:-0}" != "1" ]]; then
  open "$mount_point" >/dev/null 2>&1 || true
  /usr/bin/osascript <<APPLESCRIPT
tell application "Finder"
  activate
  tell disk "$DISPLAY_NAME"
    open
    set windowRef to container window
    set current view of windowRef to icon view
    set toolbar visible of windowRef to false
    set statusbar visible of windowRef to false
    set the bounds of windowRef to {120, 120, 860, 500}
    set viewOptions to the icon view options of windowRef
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set background color of viewOptions to {65535, 65535, 65535}
    set position of item "$DISPLAY_NAME.app" of windowRef to {170, 60}
    set position of item "Applications" of windowRef to {570, 60}
    set position of item "$HELPER_NAME" of windowRef to {370, 230}
    update without registering applications
    delay 2
    close windowRef
  end tell
end tell
APPLESCRIPT
fi

rm -rf "$mount_point/.fseventsd" "$mount_point/.Trashes" "$mount_point/.Spotlight-V100"
sync
hdiutil detach "$device"
device=""
trap - EXIT

hdiutil convert "$RW_DMG_PATH" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"

hdiutil verify "$DMG_PATH"
(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$SHA_PATH")"
)

echo "Created $DMG_PATH"
echo "Created $SHA_PATH"
