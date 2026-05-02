#!/bin/bash
# Build + wrap as .app + launch
set -e
cd "$(dirname "$0")/.."
swift build -c release
APP=".build/Kurley.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Kurley "$APP/Contents/MacOS/Kurley"
ICON_SRC="Kurley/Resources/Kurley.icns"
if [ ! -f "$ICON_SRC" ] || [ "Kurley/Resources/kurley.svg" -nt "$ICON_SRC" ]; then
  ./scripts/make-icon.swift Kurley/Resources/kurley.svg "$ICON_SRC"
fi
cp "$ICON_SRC" "$APP/Contents/Resources/Kurley.icns"

# Bundle Python toolkit (analyze.py + kurley/ package) for runtime discovery.
mkdir -p "$APP/Contents/Resources/scripts"
cp scripts/analyze.py "$APP/Contents/Resources/scripts/analyze.py"
rsync -a --exclude '__pycache__' scripts/kurley/ "$APP/Contents/Resources/scripts/kurley/"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Kurley</string>
  <key>CFBundleExecutable</key><string>Kurley</string>
  <key>CFBundleIconFile</key><string>Kurley</string>
  <key>CFBundleIdentifier</key><string>com.refulfil.kurley</string>
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
  rm -rf /Applications/Kurley.app
  cp -R "$APP" /Applications/Kurley.app
  xattr -cr /Applications/Kurley.app 2>/dev/null || true
  codesign --force --deep --sign - /Applications/Kurley.app 2>/dev/null || true
  open /Applications/Kurley.app
else
  open "$APP"
fi
