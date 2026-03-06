#!/bin/bash
#
# bundle.sh — Package the dm-app binary into a macOS .app bundle.
#
# Usage:
#   ./scripts/bundle.sh [release|debug]
#
# Output:
#   ./build/DownloadsManager.app
#

set -euo pipefail

CONFIG="${1:-release}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="DownloadsManager"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
BUNDLE_ID="io.rks.downloads-manager"

echo "Building dm-app ($CONFIG)..."
cd "$PROJECT_DIR"
swift build -c "$CONFIG" --product dm-app

# Find the binary
if [ "$CONFIG" = "release" ]; then
    BINARY="$(swift build -c release --product dm-app --show-bin-path)/dm-app"
else
    BINARY="$(swift build -c debug --product dm-app --show-bin-path)/dm-app"
fi

echo "Binary: $BINARY"

# Create .app bundle structure
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp "$BINARY" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Generate Info.plist
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>Downloads Manager</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc code sign
codesign --force --sign - "$APP_DIR"

echo ""
echo "Done: $APP_DIR"
echo ""
echo "To run:  open $APP_DIR"
echo "To install: cp -R $APP_DIR /Applications/"
