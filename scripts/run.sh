#!/bin/bash
# Build + wrap as .app + launch
set -e
cd "$(dirname "$0")/.."
swift build -c release
APP=".build/Modulr.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Modulr "$APP/Contents/MacOS/Modulr"
ICON_SRC="Modulr/Resources/Modulr.icns"
if [ ! -f "$ICON_SRC" ] || [ "Modulr/Resources/modulr.svg" -nt "$ICON_SRC" ]; then
  ./scripts/make-icon.swift Modulr/Resources/modulr.svg "$ICON_SRC"
fi
cp "$ICON_SRC" "$APP/Contents/Resources/Modulr.icns"

# Compile the asset catalog so NSAccentColorName resolves the brand accent,
# which AppKit-backed table selection reads (SwiftUI .tint cannot reach it).
# actool ships only with full Xcode, so resolve its developer dir explicitly
# (the default xcrun points at CommandLineTools, which lacks actool).
ASSETS="Modulr/Resources/Assets.xcassets"
XCODE_DEV="$(xcode-select -p 2>/dev/null)"
[ -x "$XCODE_DEV/usr/bin/actool" ] || XCODE_DEV="/Applications/Xcode.app/Contents/Developer"
if [ -d "$ASSETS" ] && [ -x "$XCODE_DEV/usr/bin/actool" ]; then
  DEVELOPER_DIR="$XCODE_DEV" xcrun actool "$ASSETS" \
    --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 14.0 \
    --output-partial-info-plist /tmp/modulr-actool.plist >/dev/null 2>&1 || true
fi

# Bundle Python toolkit (analyze.py + modulr/ package) for runtime discovery.
mkdir -p "$APP/Contents/Resources/scripts"
cp scripts/analyze.py "$APP/Contents/Resources/scripts/analyze.py"
rsync -a --exclude '__pycache__' scripts/modulr/ "$APP/Contents/Resources/scripts/modulr/"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Modulr</string>
  <key>CFBundleExecutable</key><string>Modulr</string>
  <key>CFBundleIconFile</key><string>Modulr</string>
  <key>NSAccentColorName</key><string>AccentColor</string>
  <key>CFBundleIdentifier</key><string>com.fromlost.modulr</string>
  <key>CFBundleVersion</key><string>0.1</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Audio File</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.mp3</string>
        <string>public.mpeg-4-audio</string>
        <string>com.apple.m4a-audio</string>
        <string>public.aiff-audio</string>
        <string>com.microsoft.waveform-audio</string>
        <string>public.aac-audio</string>
        <string>org.xiph.flac</string>
        <string>public.audio</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
EOF
# Strip quarantine + ad-hoc sign so Gatekeeper trusts the app for handling files.
xattr -cr "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP" 2>/dev/null || true

if [ "$1" = "--install" ]; then
  rm -rf /Applications/Modulr.app
  cp -R "$APP" /Applications/Modulr.app
  xattr -cr /Applications/Modulr.app 2>/dev/null || true
  codesign --force --deep --sign - /Applications/Modulr.app 2>/dev/null || true
  open /Applications/Modulr.app
else
  open "$APP"
fi
