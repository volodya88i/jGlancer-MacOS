#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/_common.sh
command -v xcodegen >/dev/null || { echo "xcodegen not found: brew install xcodegen" >&2; exit 1; }
xcodegen generate --quiet
# Build against the same dependency pins as the JGCore package (the generated project is not in git).
RESOLVED_DIR="$APP_NAME.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "$RESOLVED_DIR"
cp Packages/JGCore/Package.resolved "$RESOLVED_DIR/Package.resolved"
FMT=cat
command -v xcbeautify >/dev/null && FMT="xcbeautify --quiet"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
  -configuration "${CONFIG:-Debug}" -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath build/DerivedData build | $FMT
echo "Built build/DerivedData/Build/Products/${CONFIG:-Debug}/$APP_NAME.app"
