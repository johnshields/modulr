#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP=".build/Modulr.app"
DIST="dist"

./scripts/run.sh --package

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$DIST/Modulr-$VERSION.dmg"
mkdir -p "$DIST"
rm -f "$DMG"

if [ -n "${DEVELOPER_ID:-}" ]; then
  codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
fi

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/Modulr.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Modulr" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
echo "Built $DMG (version $VERSION)"
echo "sha256 $SHA"
