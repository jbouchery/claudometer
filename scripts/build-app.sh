#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"

swift build -c release

APP=Claudometer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Claudometer "$APP/Contents/MacOS/Claudometer"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Claudometer</string>
    <key>CFBundleIdentifier</key>
    <string>com.claudometer.app</string>
    <key>CFBundleName</key>
    <string>Claudometer</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMultipleInstancesProhibited</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
EOF

# Ad-hoc signature: no identity, but seals the bundle so macOS sees the same app
# across rebuilds (permissions, login item) and satisfies the ARM64 signed-code rule.
codesign --force --sign - "$APP"

ZIP="Claudometer-${VERSION}.zip"
rm -f Claudometer-*.zip
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Built $APP ($VERSION) and $ZIP"
