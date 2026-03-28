#!/bin/bash
set -euo pipefail

# CLI Pulse - App Store Build & Upload Script
# Usage: ./scripts/build-appstore.sh [macos|ios|all] [--upload]
#
# Prerequisites:
#   - Valid Apple Developer signing certificates
#   - API key at: ~/Library/Mobile Documents/com~apple~CloudDocs/Downloads/AuthKey_DMMFP6XTXX.p8
#   - App Store Connect app created (ID: 6761163709)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT="$PROJECT_DIR/CLI Pulse Bar.xcodeproj"
BUILD_DIR="$PROJECT_DIR/build/appstore"

# App Store Connect credentials
API_KEY_ID="DMMFP6XTXX"
API_ISSUER="c5671c11-49ec-47d9-bd38-5e3c1a249416"
API_KEY_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Downloads/AuthKey_${API_KEY_ID}.p8"
TEAM_ID="KHMK6Q3L3K"

# Parse arguments
PLATFORM="${1:-all}"
UPLOAD=false
if [[ "${2:-}" == "--upload" ]] || [[ "${1:-}" == "--upload" ]]; then
    UPLOAD=true
    if [[ "${1:-}" == "--upload" ]]; then
        PLATFORM="all"
    fi
fi

VERSION=$(defaults read "$PROJECT_DIR/CLI Pulse Bar/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "0.1.0")

echo "================================================"
echo "  CLI Pulse - App Store Build v${VERSION}"
echo "  Platform: ${PLATFORM}"
echo "  Upload: ${UPLOAD}"
echo "================================================"
echo ""

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# --- macOS Build ---
build_macos() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Building macOS..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local ARCHIVE="$BUILD_DIR/CLIPulseBar-macOS.xcarchive"
    local EXPORT="$BUILD_DIR/macos-export"

    echo "[1/3] Archiving macOS target..."
    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "CLI Pulse Bar" \
        -configuration Release \
        -archivePath "$ARCHIVE" \
        -quiet \
        -allowProvisioningUpdates \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        CODE_SIGN_STYLE=Automatic

    echo "  ✓ Archive: $ARCHIVE"

    echo "[2/3] Exporting for App Store..."
    cat > "$BUILD_DIR/ExportOptions-macOS.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>teamID</key>
    <string>KHMK6Q3L3K</string>
    <key>destination</key>
    <string>export</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE" \
        -exportOptionsPlist "$BUILD_DIR/ExportOptions-macOS.plist" \
        -exportPath "$EXPORT" \
        -allowProvisioningUpdates \
        -quiet 2>&1 || true

    echo "  ✓ Export: $EXPORT"

    if [[ "$UPLOAD" == true ]]; then
        echo "[3/3] Uploading macOS to App Store Connect..."
        upload_to_appstore "$ARCHIVE" "$EXPORT" "macos"
    else
        echo "[3/3] Skipping upload (use --upload to enable)"
    fi
    echo ""
}

# --- iOS Build (includes Widgets) ---
build_ios() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Building iOS (includes Widgets)..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local ARCHIVE="$BUILD_DIR/CLIPulse-iOS.xcarchive"
    local EXPORT="$BUILD_DIR/ios-export"

    echo "[1/3] Archiving iOS target..."
    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "CLI Pulse iOS" \
        -configuration Release \
        -archivePath "$ARCHIVE" \
        -destination "generic/platform=iOS" \
        -quiet \
        -allowProvisioningUpdates \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        CODE_SIGN_STYLE=Automatic

    echo "  ✓ Archive: $ARCHIVE"

    echo "[2/3] Exporting for App Store..."
    cat > "$BUILD_DIR/ExportOptions-iOS.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>teamID</key>
    <string>KHMK6Q3L3K</string>
    <key>destination</key>
    <string>export</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE" \
        -exportOptionsPlist "$BUILD_DIR/ExportOptions-iOS.plist" \
        -exportPath "$EXPORT" \
        -allowProvisioningUpdates \
        -quiet 2>&1 || true

    echo "  ✓ Export: $EXPORT"

    if [[ "$UPLOAD" == true ]]; then
        echo "[3/3] Uploading iOS to App Store Connect..."
        upload_to_appstore "$ARCHIVE" "$EXPORT" "ios"
    else
        echo "[3/3] Skipping upload (use --upload to enable)"
    fi
    echo ""
}

# --- watchOS Build ---
build_watchos() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Building watchOS..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local ARCHIVE="$BUILD_DIR/CLIPulse-watchOS.xcarchive"
    local EXPORT="$BUILD_DIR/watchos-export"

    echo "[1/3] Archiving watchOS target..."
    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "CLI Pulse Watch" \
        -configuration Release \
        -archivePath "$ARCHIVE" \
        -destination "generic/platform=watchOS" \
        -quiet \
        -allowProvisioningUpdates \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        CODE_SIGN_STYLE=Automatic

    echo "  ✓ Archive: $ARCHIVE"

    echo "[2/3] Exporting for App Store..."
    cat > "$BUILD_DIR/ExportOptions-watchOS.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>KHMK6Q3L3K</string>
    <key>destination</key>
    <string>export</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE" \
        -exportOptionsPlist "$BUILD_DIR/ExportOptions-watchOS.plist" \
        -exportPath "$EXPORT" \
        -allowProvisioningUpdates \
        -quiet 2>&1 || true

    echo "  ✓ Export: $EXPORT"

    if [[ "$UPLOAD" == true ]]; then
        echo "[3/3] Uploading watchOS to App Store Connect..."
        upload_to_appstore "$ARCHIVE" "$EXPORT" "watchos"
    else
        echo "[3/3] Skipping upload (use --upload to enable)"
    fi
    echo ""
}

# --- Upload function ---
upload_to_appstore() {
    local ARCHIVE_PATH="$1"
    local EXPORT_DIR="$2"
    local PLATFORM="$3"

    if [[ ! -f "$API_KEY_PATH" ]]; then
        echo "  ERROR: API key not found at $API_KEY_PATH"
        echo "  Download from App Store Connect > Users and Access > Keys"
        return 1
    fi

    echo "  Uploading via xcodebuild -exportArchive (destination: upload)..."

    local EXPORT_PLIST="$BUILD_DIR/ExportOptions-${PLATFORM}-upload.plist"
    cat > "$EXPORT_PLIST" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>KHMK6Q3L3K</string>
    <key>destination</key>
    <string>upload</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportOptionsPlist "$EXPORT_PLIST" \
        -exportPath "$EXPORT_DIR" \
        -allowProvisioningUpdates \
        -authenticationKeyPath "$API_KEY_PATH" \
        -authenticationKeyID "$API_KEY_ID" \
        -authenticationKeyIssuerID "$API_ISSUER" \
        2>&1

    echo "  ✓ Upload complete for $PLATFORM"
}

# --- Execute ---
case "$PLATFORM" in
    macos)
        build_macos
        ;;
    ios)
        build_ios
        ;;
    watchos)
        build_watchos
        ;;
    all)
        build_macos
        build_ios
        build_watchos
        ;;
    *)
        echo "Usage: $0 [macos|ios|watchos|all] [--upload]"
        exit 1
        ;;
esac

# --- Summary ---
echo "================================================"
echo "  Build Complete!"
echo "================================================"
echo ""
echo "  Archives:"
ls -1 "$BUILD_DIR"/*.xcarchive 2>/dev/null | while read f; do echo "    $f"; done
echo ""
echo "  Exports:"
ls -1d "$BUILD_DIR"/*-export 2>/dev/null | while read f; do echo "    $f"; done
echo ""
if [[ "$UPLOAD" == false ]]; then
    echo "  To upload: $0 $PLATFORM --upload"
fi
echo ""
