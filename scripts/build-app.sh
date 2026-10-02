#!/bin/zsh
# Builds build/Dynamic Lighting.app (Apple Silicon, ad-hoc signed unless SIGN_IDENTITY is set).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
APP="build/Dynamic Lighting.app"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/DynamicLighting"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/DynamicLighting"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Dynamic Lighting</string>
    <key>CFBundleDisplayName</key><string>Dynamic Lighting</string>
    <key>CFBundleIdentifier</key><string>io.github.ondrejbohac.mac-dynamic-lighting</string>
    <key>CFBundleExecutable</key><string>DynamicLighting</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --sign "${SIGN_IDENTITY:--}" --options runtime "$APP"
echo "Built $APP"
