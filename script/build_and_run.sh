#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="ZCodeAccountSwitcher"
BUNDLE_ID="com.zcode.account-switcher.mac"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
PROJECT_FILE="$ROOT_DIR/ZCodeAccountSwitcher.xcodeproj"
DERIVED_DATA="$ROOT_DIR/.build/xcode-derived-data"
BUILT_APP="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

if [[ ! -d "$PROJECT_FILE" ]]; then
  if ! command -v xcodegen >/dev/null 2>&1; then
    echo "ZCodeAccountSwitcher.xcodeproj is missing. Install XcodeGen or run xcodegen generate first." >&2
    exit 1
  fi
  (cd "$ROOT_DIR" && xcodegen generate)
fi

xcodebuild build \
  -project "$PROJECT_FILE" \
  -scheme "$APP_NAME" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA"

rm -rf "$APP_BUNDLE"
mkdir -p "$DIST_DIR"
ditto "$BUILT_APP" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n -F "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
