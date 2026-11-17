#!/usr/bin/env bash
# Runs all unit tests through the Xcode scheme (same as ⌘U).
# Faster for logic-only changes:  swift test --package-path Packages/MetroCore
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
xcodebuild -project MetroNetwork.xcodeproj -scheme MetroNetwork \
           -derivedDataPath build/DerivedData -destination 'platform=macOS,arch=arm64' test
