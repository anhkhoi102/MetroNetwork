#!/usr/bin/env bash
# Builds the iOS app for the Simulator (no Apple Developer account needed).
# Usage:  Scripts/build-ios.sh [debug|release]
set -euo pipefail
case "${1:-debug}" in
    release) CONFIG="Release" ;;
    debug)   CONFIG="Debug" ;;
    *) echo "Usage: $0 [debug|release]" >&2; exit 1 ;;
esac
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
DERIVED="$PROJECT_ROOT/build/DerivedData-iOS"
echo "==> xcodebuild iOS Simulator ($CONFIG)…"
xcodebuild -project MetroNetwork.xcodeproj -scheme MetroNetwork -configuration "$CONFIG" \
           -derivedDataPath "$DERIVED" -sdk iphonesimulator \
           -destination 'generic/platform=iOS Simulator' build -quiet \
           2> >(grep -v "failed with exit code 0 but produced no further output" >&2)
APP="$DERIVED/Build/Products/$CONFIG-iphonesimulator/MetroNetwork.app"
[[ -d "$APP" ]] || { echo "error: $APP not found" >&2; exit 1; }
echo "==> Done: $APP"
echo "    Install on the booted simulator:  xcrun simctl install booted \"$APP\" && xcrun simctl launch booted io.github.metronetwork.game"
