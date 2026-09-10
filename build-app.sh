#!/bin/zsh
# Build a menu-bar-only .app bundle from the SwiftPM executable.
# Usage: ./build-app.sh            # debug build + launch instructions
#        ./build-app.sh --release  # optimized build for daily use
set -euo pipefail

APPNAME="ResourceMonitorWidget"
BUNDLE="Resource Monitor.app"

CONFIG="debug"

if [[ "${1:-}" == "--release" ]]; then
  CONFIG="release"
fi

swift build -c "$CONFIG"

BIN=$(swift build -c "$CONFIG" --show-bin-path)/ResourceMonitorWidget
CONTENTS="$BUNDLE/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN" "$CONTENTS/MacOS/$APPNAME"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>ResourceMonitorWidget</string>
  <key>CFBundleIdentifier</key><string>com.example.resourcemonitorwidget</string>
  <key>CFBundleName</key><string>Resource Monitor</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# App icon: render the .iconset from the master artwork and build AppIcon.icns.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" "512:icon_256x256@2x" "512:icon_512x512" "1024:icon_512x512@2x"; do
  px="${spec%%:*}"; name="${spec##*:}"
  /usr/bin/sips -s format png -z "$px" "$px" Assets/icon-1024.png --out "$ICONSET/$name.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# Ad-hoc sign so it launches without Gatekeeper friction locally.
/usr/bin/codesign --force --deep --sign - "$BUNDLE" 2>/dev/null || true

echo "Built $BUNDLE"
echo "Launch with: open \"$BUNDLE\""
echo "Menu bar icons appear right away (CPU / Memory / Storage)."
echo "Per-icon % and widget visibility toggles live in each widget's right-click menu."
