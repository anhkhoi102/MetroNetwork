#!/usr/bin/env bash
#
# Builds Metro Network for macOS and copies the app to build/MetroNetwork.app.
#
# Usage:
#   Scripts/build.sh                 # Release
#   Scripts/build.sh debug           # Debug
#   Scripts/build.sh release --open  # build, then launch

set -euo pipefail

CONFIG_ARG="${1:-release}"
OPEN_AFTER="${2:-}"
case "$CONFIG_ARG" in
    release) CONFIG="Release" ;;
    debug)   CONFIG="Debug" ;;
    *) echo "Usage: $0 [release|debug] [--open]" >&2; exit 1 ;;
esac

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
BUILD_DIR="$PROJECT_ROOT/build"
DERIVED="$BUILD_DIR/DerivedData"
APP_OUT="$BUILD_DIR/MetroNetwork.app"

echo "==> xcodebuild macOS ($CONFIG)…"
xcodebuild -project MetroNetwork.xcodeproj -scheme MetroNetwork \
           -configuration "$CONFIG" -derivedDataPath "$DERIVED" \
           -destination 'platform=macOS,arch=arm64' build -quiet \
           2> >(grep -v "failed with exit code 0 but produced no further output" >&2)

PRODUCT="$DERIVED/Build/Products/$CONFIG/MetroNetwork.app"
[[ -d "$PRODUCT" ]] || { echo "error: $PRODUCT not found" >&2; exit 1; }

if [[ -d "$APP_OUT" && "$APP_OUT" == "$BUILD_DIR/"*.app ]]; then rm -r "$APP_OUT"; fi
ditto "$PRODUCT" "$APP_OUT"
codesign --verify --strict "$APP_OUT"

echo "==> Done: $APP_OUT ($(du -sh "$APP_OUT" | cut -f1))"
[[ "$OPEN_AFTER" == "--open" ]] && open "$APP_OUT"
exit 0
