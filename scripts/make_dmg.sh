#!/usr/bin/env bash
# Builds the Release app and packs it into build/dist/<App>-<version>.dmg (docs/RELEASE.md).
#
# Without settings the DMG holds the ad-hoc signed build (for testing on this Mac only).
# For a release:
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"  signs with hardened runtime and a timestamp;
#   NOTARY_PROFILE=<keychain profile from `xcrun notarytool store-credentials`>  notarizes and staples.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/_common.sh

echo "== Building (Release)"
CONFIG=Release scripts/build.sh > build/release.log 2>&1 || { tail -20 build/release.log; exit 1; }
APP="build/DerivedData/Build/Products/Release/$APP_NAME.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DIST=build/dist
STAGE="$DIST/stage"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  echo "== Signing with $SIGN_IDENTITY"
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$STAGE/$APP_NAME.app"
  codesign --verify --strict --verbose=2 "$STAGE/$APP_NAME.app"
else
  echo "== No SIGN_IDENTITY: the DMG holds the ad-hoc signed build (this Mac only)"
fi

echo "== Packing $DMG"
rm -f "$DMG"
# `hdiutil create` is deprecated from macOS 27; `diskutil image` makes an APFS volume, which every supported macOS
# (14+) mounts. Older build Macs keep hdiutil.
if diskutil image create from --help > /dev/null 2>&1; then
  # Its progress line has no line break: shown only when it fails.
  if ! PACK_LOG="$(diskutil image create from --format UDZO --volumeName "$APP_NAME" "$STAGE" "$DMG" 2>&1)"; then
    echo "$PACK_LOG"
    exit 1
  fi
else
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -format UDZO -fs HFS+ "$DMG" > /dev/null
fi
rm -rf "$STAGE"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi
if [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "== Notarizing (this waits for Apple)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi
echo "== Done: $DMG ($(du -h "$DMG" | cut -f1))"
