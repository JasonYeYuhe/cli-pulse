#!/bin/bash
set -euo pipefail

# CLI Pulse Bar - Release Build Script
# Usage: ./scripts/build-release.sh [--notarize]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT="$PROJECT_DIR/CLI Pulse Bar.xcodeproj"
SCHEME="CLI Pulse Bar"
APP_NAME="CLI Pulse Bar"

BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

VERSION=$(defaults read "$PROJECT_DIR/CLI Pulse Bar/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "0.1.0")
DMG_FINAL="$BUILD_DIR/${APP_NAME}-v${VERSION}.dmg"

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
echo "[2/6] Archiving..."
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -quiet \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    2>&1 | tail -5

echo "  Archive created at: $ARCHIVE_PATH"

# Export
echo "[3/6] Exporting app..."
cat > "$BUILD_DIR/ExportOptions.plist" << 'EXPORTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>-</string>
</dict>
</plist>
EXPORTEOF

# Direct copy from archive instead of export (works without dev account)
APP_IN_ARCHIVE="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
if [[ -d "$APP_IN_ARCHIVE" ]]; then
    mkdir -p "$EXPORT_PATH"
    cp -R "$APP_IN_ARCHIVE" "$EXPORT_PATH/"
    echo "  Exported to: $EXPORT_PATH/$APP_NAME.app"
else
    # Fallback: copy from Products in archive
    APP_IN_USR="$ARCHIVE_PATH/Products/usr/local/bin/$APP_NAME.app"
    if [[ -d "$APP_IN_USR" ]]; then
        mkdir -p "$EXPORT_PATH"
        cp -R "$APP_IN_USR" "$EXPORT_PATH/"
    else
        echo "  ERROR: Could not find app in archive. Listing contents:"
        find "$ARCHIVE_PATH/Products" -name "*.app" 2>/dev/null
        exit 1
    fi
fi

# Ad-hoc sign
echo "[4/6] Code signing (ad-hoc)..."
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
