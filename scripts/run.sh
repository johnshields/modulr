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

# Bundle Python toolkit (analyze.py + modulr/ package) for runtime discovery.
mkdir -p "$APP/Contents/Resources/scripts"
cp scripts/analyze.py "$APP/Contents/Resources/scripts/analyze.py"
rsync -a --exclude '__pycache__' scripts/modulr/ "$APP/Contents/Resources/scripts/modulr/"

MUTAGEN_DIR="$(python3 -c 'import mutagen, os; print(os.path.dirname(mutagen.__file__))' 2>/dev/null || true)"
if [ -n "$MUTAGEN_DIR" ] && [ -d "$MUTAGEN_DIR" ]; then
  rsync -a --exclude '__pycache__' "$MUTAGEN_DIR" "$APP/Contents/Resources/scripts/"
fi
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Modulr</string>
  <key>CFBundleExecutable</key><string>Modulr</string>
  <key>CFBundleDisplayName</key><string>Modulr</string>
  <key>CFBundleIconFile</key><string>Modulr</string>
  <key>CFBundleIdentifier</key><string>com.fromlost.modulr</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 fromlost</string>
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

case "${1:-}" in
  --install)
    rm -rf /Applications/Modulr.app
    cp -R "$APP" /Applications/Modulr.app
    xattr -cr /Applications/Modulr.app 2>/dev/null || true
    codesign --force --deep --sign - /Applications/Modulr.app 2>/dev/null || true
    open /Applications/Modulr.app
    ;;
  --package)
    ;;
  *)
    open "$APP"
    ;;
esac
