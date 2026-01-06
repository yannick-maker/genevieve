#!/bin/bash
set -e

APP_NAME="Genevieve"
BUILD_DIR=".build/release"
APP_BUNDLE="$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Building $APP_NAME..."

# Build release version
swift build -c release

# Clean previous bundle
rm -rf "$APP_BUNDLE"

# Create app bundle structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/"

# Copy Info.plist
cp "Genevieve/Resources/Info.plist" "$CONTENTS_DIR/"

# Copy and compile assets if xcrun is available
if command -v xcrun &> /dev/null; then
    echo "Compiling asset catalog..."
    xcrun actool Genevieve/Resources/Assets.xcassets \
        --compile "$RESOURCES_DIR" \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        --app-icon AppIcon \
        --output-partial-info-plist /tmp/assetcatalog_generated_info.plist \
        2>/dev/null || echo "Asset compilation skipped"
fi

# Copy entitlements for reference
cp "Genevieve/Resources/Genevieve.entitlements" "$CONTENTS_DIR/"

# Code sign the app (ad-hoc for development)
echo "Code signing..."
codesign --force --deep --sign - \
    --entitlements "Genevieve/Resources/Genevieve.entitlements" \
    "$APP_BUNDLE"

echo ""
echo "Build complete: $APP_BUNDLE"
echo ""
echo "To run: open $APP_BUNDLE"
echo "Or:     ./$APP_BUNDLE/Contents/MacOS/Genevieve"
echo ""
echo "NOTE: After first launch, go to:"
echo "  System Settings → Privacy & Security → Accessibility"
echo "  and enable Genevieve"
