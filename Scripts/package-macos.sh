#!/usr/bin/env bash
#
# Builds a universal (Apple Silicon + Intel) Release of Metro Network for macOS and zips it for download:
#   dist/MetroNetwork-<version>-macOS.zip   and its SHA-256 checksum.
#
# The app is ad-hoc signed (no Apple developer account is needed to build it), so macOS asks for confirmation
# the first time it is opened: see "Install" in README.md.

set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
DERIVED="$PROJECT_ROOT/build/DerivedData-Package"
DIST="$PROJECT_ROOT/dist"

echo "==> xcodebuild macOS Release (arm64 + x86_64)…"
xcodebuild -project MetroNetwork.xcodeproj -scheme MetroNetwork -configuration Release \
           -derivedDataPath "$DERIVED" -destination 'generic/platform=macOS' \
           ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY="-" build -quiet \
           2> >(grep -v "failed with exit code 0 but produced no further output" >&2)

APP="$DERIVED/Build/Products/Release/MetroNetwork.app"
[[ -d "$APP" ]] || { echo "error: $APP not found" >&2; exit 1; }
# Remove debug and local symbols: they record the build machine's file paths (and make the app bigger).
strip -S -x "$APP/Contents/MacOS/MetroNetwork"
codesign --force --sign - --entitlements SupportingFiles/MetroNetwork.entitlements --options runtime "$APP"
codesign --verify --strict "$APP"
if LC_ALL=C grep -qa -e "/Users/" -e "$HOME" "$APP/Contents/MacOS/MetroNetwork"; then
    echo "error: the binary still contains local file paths" >&2; exit 1
fi
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
echo "==> Version $VERSION, architectures: $(lipo -archs "$APP/Contents/MacOS/MetroNetwork")"

mkdir -p "$DIST"
ZIP="$DIST/MetroNetwork-$VERSION-macOS.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(cd "$DIST" && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
echo "==> $ZIP ($(du -h "$ZIP" | cut -f1))"
cat "$ZIP.sha256"
