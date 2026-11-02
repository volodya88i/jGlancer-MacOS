#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for pkg in Packages/*/; do
  [ -f "$pkg/Package.swift" ] || continue
  echo "== swift test: $pkg"
  swift test --package-path "$pkg"
done
# If an app test target exists, run it too:
source scripts/_common.sh
if [ -d "$APP_NAME.xcodeproj" ] && xcodebuild -list -project "$APP_NAME.xcodeproj" 2>/dev/null | grep -q "${APP_NAME}Tests"; then
  xcodebuild test -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath build/DerivedData
fi
