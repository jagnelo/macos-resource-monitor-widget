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
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so it launches without Gatekeeper friction locally.
/usr/bin/codesign --force --deep --sign - "$BUNDLE" 2>/dev/null || true

echo "Built $BUNDLE"
echo "Launch with: open \"$BUNDLE\""
echo "Menu bar icons appear right away (CPU / Memory / Storage)."
echo "Per-icon % and widget visibility toggles live in each widget's right-click menu."
