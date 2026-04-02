#!/bin/bash
set -euo pipefail

# CLI Pulse Bar - Release Build Script
# Usage: ./scripts/build-release.sh [--notarize]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT="$PROJECT_DIR/CLI Pulse Bar.xcodeproj"
SCHEME="CLI Pulse Bar"
APP_NAME="CLI Pulse Bar"
DMG_BASENAME="CLI-Pulse-Bar"

BUILD_DIR="$PROJECT_DIR/build"
EXPORT_PATH="$BUILD_DIR/export"
DERIVED_DATA_PATH="$BUILD_DIR/DerivedData"
SHOW_SETTINGS=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null)
VERSION=$(printf "%s\n" "$SHOW_SETTINGS" | awk -F' = ' '/MARKETING_VERSION = / {print $2; exit}')
if [[ -z "${VERSION:-}" ]]; then
    VERSION="0.1.0"
fi
DMG_FINAL="$BUILD_DIR/${DMG_BASENAME}-v${VERSION}.dmg"

NOTARIZE=false
if [[ "${1:-}" == "--notarize" ]]; then
    NOTARIZE=true
fi

echo "================================================"
echo "  CLI Pulse Bar - Release Build v${VERSION}"
echo "================================================"
echo ""

# Clean
echo "[1/6] Cleaning previous build..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Archive
echo "[2/6] Building Release app..."
xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -quiet \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    DEVELOPMENT_TEAM="" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    2>&1 | tail -5

APP_BUILD_DIR="$DERIVED_DATA_PATH/Build/Products/Release"
APP_IN_BUILD="$APP_BUILD_DIR/$APP_NAME.app"
echo "  Build products at: $APP_BUILD_DIR"

# Export
echo "[3/6] Exporting app..."
mkdir -p "$EXPORT_PATH"
if [[ -d "$APP_IN_BUILD" ]]; then
    rm -rf "$EXPORT_PATH/$APP_NAME.app"
    cp -R "$APP_IN_BUILD" "$EXPORT_PATH/"
    echo "  Exported to: $EXPORT_PATH/$APP_NAME.app"
else
    echo "  ERROR: Could not find built app at: $APP_IN_BUILD"
    find "$APP_BUILD_DIR" -name "*.app" 2>/dev/null || true
    exit 1
fi

# Ad-hoc sign
echo "[4/6] Code signing (ad-hoc)..."
xattr -cr "$EXPORT_PATH/$APP_NAME.app"
codesign --force --deep --sign - "$EXPORT_PATH/$APP_NAME.app"
echo "  Signed successfully"

# Create DMG
echo "[5/6] Creating DMG..."
DMG_STAGING="$BUILD_DIR/dmg-staging"
mkdir -p "$DMG_STAGING"
cp -R "$EXPORT_PATH/$APP_NAME.app" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_FINAL" \
    -quiet

rm -rf "$DMG_STAGING"
echo "  DMG created: $DMG_FINAL"

# Notarize (optional)
if [[ "$NOTARIZE" == true ]]; then
    echo "[6/6] Notarizing..."
    echo ""
    echo "  To notarize, you need an Apple Developer account."
    echo "  Set these environment variables:"
    echo "    APPLE_ID=your@email.com"
    echo "    APPLE_TEAM_ID=YOUR_TEAM_ID"
    echo "    APPLE_APP_PASSWORD=app-specific-password"
    echo ""

    if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
        xcrun notarytool submit "$DMG_FINAL" \
            --apple-id "$APPLE_ID" \
            --team-id "$APPLE_TEAM_ID" \
            --password "$APPLE_APP_PASSWORD" \
            --wait

        xcrun stapler staple "$DMG_FINAL"
        echo "  Notarization complete!"
    else
        echo "  Skipping - environment variables not set"
    fi
else
    echo "[6/6] Skipping notarization (use --notarize to enable)"
fi

# Summary
echo ""
echo "================================================"
echo "  Build Complete!"
echo "================================================"
echo ""
echo "  App:     $EXPORT_PATH/$APP_NAME.app"
echo "  DMG:     $DMG_FINAL"
echo "  Size:    $(du -sh "$DMG_FINAL" | cut -f1)"
echo ""
echo "  To test: open \"$EXPORT_PATH/$APP_NAME.app\""
echo "  To distribute: share $DMG_FINAL"
echo ""
