#!/bin/bash
set -euo pipefail

# CLI Pulse — Cross-Platform Version Sync
# Compares iOS and Android versions, bumps the lower one, builds & publishes.
# iOS → App Store Connect | Android → GitHub Releases (public repo)
#
# Usage: ./scripts/sync-versions.sh [--dry-run]
# Designed to run as a daily scheduled task.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$PROJECT_DIR")"
ANDROID_DIR="$REPO_ROOT/android"
PBXPROJ="$PROJECT_DIR/CLI Pulse Bar.xcodeproj/project.pbxproj"
GRADLE_FILE="$ANDROID_DIR/app/build.gradle.kts"

# App Store Connect credentials — set via environment or .env file
API_KEY_ID="${ASC_API_KEY_ID:?Set ASC_API_KEY_ID environment variable}"
API_ISSUER="${ASC_API_ISSUER:?Set ASC_API_ISSUER environment variable}"
API_KEY_PATH="${ASC_API_KEY_PATH:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/Downloads/AuthKey_${API_KEY_ID}.p8}"
TEAM_ID="${ASC_TEAM_ID:?Set ASC_TEAM_ID environment variable}"
APP_ID="${ASC_APP_ID:?Set ASC_APP_ID environment variable}"

# Public repo for Android releases
PUBLIC_REPO="JasonYeYuhe/cli-pulse"

# Java for Android builds
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk}"
export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ============================================================
# Version reading
# ============================================================

read_ios_version() {
    grep "MARKETING_VERSION" "$PBXPROJ" | head -1 | sed 's/.*= //;s/;//;s/ //g'
}

read_ios_build() {
    grep "CURRENT_PROJECT_VERSION" "$PBXPROJ" | head -1 | sed 's/.*= //;s/;//;s/ //g'
}

read_android_version() {
    grep 'versionName' "$GRADLE_FILE" | head -1 | sed 's/.*"\(.*\)".*/\1/'
}

read_android_build() {
    grep 'versionCode' "$GRADLE_FILE" | head -1 | sed 's/[^0-9]//g'
}

# Compare semver: returns 0 if equal, 1 if a > b, 2 if a < b
compare_versions() {
    local a="$1" b="$2"
    if [[ "$a" == "$b" ]]; then echo 0; return; fi
    local IFS=.
    local -a av=($a) bv=($b)
    for i in 0 1 2; do
        local ai="${av[$i]:-0}" bi="${bv[$i]:-0}"
        if (( ai > bi )); then echo 1; return; fi
        if (( ai < bi )); then echo 2; return; fi
    done
    echo 0
}

# ============================================================
# Version bumping
# ============================================================

bump_ios_version() {
    local new_version="$1"
    local old_build
    old_build=$(read_ios_build)
    local new_build=$((old_build + 1))

    log "Bumping iOS: $(read_ios_version) (build $old_build) → $new_version (build $new_build)"
    if $DRY_RUN; then return; fi

    sed -i '' "s/MARKETING_VERSION = .*/MARKETING_VERSION = $new_version;/g" "$PBXPROJ"
    sed -i '' "s/CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $new_build;/g" "$PBXPROJ"
}

bump_android_version() {
    local new_version="$1"
    local old_build
    old_build=$(read_android_build)
    local new_build=$((old_build + 1))

    log "Bumping Android: $(read_android_version) (code $old_build) → $new_version (code $new_build)"
    if $DRY_RUN; then return; fi

    sed -i '' "s/versionName = \".*\"/versionName = \"$new_version\"/" "$GRADLE_FILE"
    sed -i '' "s/versionCode = .*/versionCode = $new_build/" "$GRADLE_FILE"
}

# ============================================================
# iOS: Build + Upload to App Store Connect
# ============================================================

build_and_upload_ios() {
    local version="$1"
    log "Building iOS $version for App Store..."
    if $DRY_RUN; then log "[DRY RUN] Would build and upload iOS"; return 0; fi

    cd "$PROJECT_DIR"
    local BUILD_DIR="$PROJECT_DIR/build/sync-release"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"

    # Archive
    xcodebuild archive \
        -project "CLI Pulse Bar.xcodeproj" \
        -scheme "CLI Pulse Bar" \
        -configuration Release \
        -archivePath "$BUILD_DIR/CLIPulseBar.xcarchive" \
        -quiet \
        -allowProvisioningUpdates \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        CODE_SIGN_STYLE=Automatic

    # Upload
    cat > "$BUILD_DIR/ExportOptions.plist" << 'EOF'
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
        -archivePath "$BUILD_DIR/CLIPulseBar.xcarchive" \
        -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
        -exportPath "$BUILD_DIR/export" \
        -allowProvisioningUpdates \
        -authenticationKeyPath "$API_KEY_PATH" \
        -authenticationKeyID "$API_KEY_ID" \
        -authenticationKeyIssuerID "$API_ISSUER" \
        2>&1

    log "✓ iOS $version uploaded to App Store Connect"
}

# ============================================================
# Android: Build APK + Upload to GitHub Releases
# ============================================================

build_and_upload_android() {
    local version="$1"
    log "Building Android $version..."
    if $DRY_RUN; then log "[DRY RUN] Would build and upload Android"; return 0; fi

    cd "$ANDROID_DIR"

    # Check Java
    if ! java -version &>/dev/null; then
        log "ERROR: Java not found. Set JAVA_HOME or install JDK."
        return 1
    fi

    # Build release APK
    ./gradlew assembleRelease --no-daemon -q 2>&1

    local APK_PATH
    APK_PATH=$(find "$ANDROID_DIR/app/build/outputs/apk/release" -name "*.apk" | head -1)
    if [[ -z "$APK_PATH" ]]; then
        log "ERROR: APK not found after build"
        return 1
    fi

    local RELEASE_NAME="CLI-Pulse-Android-v${version}.apk"
    cp "$APK_PATH" "/tmp/$RELEASE_NAME"

    # Upload to GitHub Releases on public repo
    local TAG="android-v${version}"
    gh release create "$TAG" "/tmp/$RELEASE_NAME#$RELEASE_NAME" \
        --repo "$PUBLIC_REPO" \
        --title "CLI Pulse Android v${version}" \
        --notes "Android release v${version} — synced with iOS version." \
        --latest=false

    rm -f "/tmp/$RELEASE_NAME"
    log "✓ Android $version uploaded to GitHub Releases ($PUBLIC_REPO)"
}

# ============================================================
# Main
# ============================================================

log "=== CLI Pulse Version Sync ==="
log "Dry run: $DRY_RUN"

IOS_VERSION=$(read_ios_version)
IOS_BUILD=$(read_ios_build)
ANDROID_VERSION=$(read_android_version)
ANDROID_BUILD=$(read_android_build)

log "iOS:     v$IOS_VERSION (build $IOS_BUILD)"
log "Android: v$ANDROID_VERSION (code $ANDROID_BUILD)"

CMP=$(compare_versions "$IOS_VERSION" "$ANDROID_VERSION")

if [[ "$CMP" == "0" ]]; then
    log "✓ Versions already in sync. Nothing to do."
    exit 0
fi

if [[ "$CMP" == "1" ]]; then
    # iOS is ahead — bump Android
    log "iOS ($IOS_VERSION) is ahead of Android ($ANDROID_VERSION)"
    TARGET_VERSION="$IOS_VERSION"
    bump_android_version "$TARGET_VERSION"

    # Build and publish Android
    if build_and_upload_android "$TARGET_VERSION"; then
        log "✓ Android synced to v$TARGET_VERSION"
    else
        log "⚠ Android build/upload failed — manual intervention needed"
    fi

elif [[ "$CMP" == "2" ]]; then
    # Android is ahead — bump iOS
    log "Android ($ANDROID_VERSION) is ahead of iOS ($IOS_VERSION)"
    TARGET_VERSION="$ANDROID_VERSION"
    bump_ios_version "$TARGET_VERSION"

    # Build and publish iOS
    if build_and_upload_ios "$TARGET_VERSION"; then
        log "✓ iOS synced to v$TARGET_VERSION"
    else
        log "⚠ iOS build/upload failed — manual intervention needed"
    fi
fi

# Commit version bump if changes were made
if ! $DRY_RUN; then
    cd "$REPO_ROOT"
    if [[ -n "$(git status --porcelain "$PBXPROJ" "$GRADLE_FILE" 2>/dev/null)" ]]; then
        git add "$PBXPROJ" "$GRADLE_FILE"
        git commit -m "chore: sync versions to v$TARGET_VERSION (iOS ↔ Android)"
        git push origin main
        log "✓ Version bump committed and pushed"
    fi
fi

log "=== Sync complete ==="
