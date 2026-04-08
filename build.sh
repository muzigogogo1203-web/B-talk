#!/bin/bash
set -e

EXECUTABLE_NAME="BTalk"
APP_NAME="B-talk"
BUILD_DIR=".build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Building $EXECUTABLE_NAME..."
swift build -c release 2>&1

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

# Copy executable
cp "$BUILD_DIR/release/$EXECUTABLE_NAME" "$MACOS/$EXECUTABLE_NAME"

# Copy Info.plist
cp "Resources/Info.plist" "$CONTENTS/Info.plist"

# Ad-hoc codesign so macOS recognizes the binary across rebuilds
# This helps preserve permissions (Input Monitoring, Accessibility, Microphone)
codesign --force --sign - --deep "$APP_BUNDLE" 2>/dev/null || true

echo "App bundle created at: $APP_BUNDLE"
echo ""
echo "To run: open $APP_BUNDLE"
echo "To grant permissions, go to System Settings > Privacy & Security"
