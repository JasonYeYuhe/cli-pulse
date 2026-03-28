#!/bin/bash
set -euo pipefail

# CLI Pulse Bar - GitHub Release Script
# Prerequisites: gh CLI authenticated, build-release.sh already run
# Usage: ./scripts/github-release.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"

VERSION=$(defaults read "$PROJECT_DIR/CLI Pulse Bar/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "0.1.0")
DMG_PATH="$BUILD_DIR/CLI Pulse Bar-v${VERSION}.dmg"
TAG="v${VERSION}"

if [[ ! -f "$DMG_PATH" ]]; then
    echo "ERROR: DMG not found at $DMG_PATH"
    echo "Run build-release.sh first."
    exit 1
fi

echo "Creating GitHub release $TAG..."
echo ""

# Generate release notes
RELEASE_NOTES=$(cat << REOF
## CLI Pulse Bar v${VERSION}

macOS menu bar app for monitoring AI coding tool usage across Claude, Codex, Gemini, OpenRouter, and Ollama.

### Features
- Menu bar presence with real-time status indicator
- Dashboard with usage metrics, cost estimates, and risk signals
- Provider usage tracking with quota visualization
- Active session monitoring
- Alert management (acknowledge, resolve, snooze)
- Configurable auto-refresh (10s - 5m)
- macOS native notifications for new alerts
- Launch at login support
- Dark/light mode support

### Installation

**Direct Download:**
1. Download \`CLI.Pulse.Bar-v${VERSION}.dmg\` below
2. Open the DMG and drag to Applications
3. Launch from Applications

**Homebrew (coming soon):**
\`\`\`bash
brew install --cask cli-pulse-bar
\`\`\`

### Requirements
- macOS 13.0 (Ventura) or later
- CLI Pulse backend running (see main repo README)
- CLI Pulse helper installed on monitored machines

### SHA256
\`\`\`
$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
\`\`\`
REOF
)

# Create release with gh CLI
gh release create "$TAG" \
    "$DMG_PATH" \
    --title "CLI Pulse Bar $TAG" \
    --notes "$RELEASE_NOTES" \
    --draft

echo ""
echo "Draft release created!"
echo "Review and publish at: https://github.com/jasonyeyuhe/cli-pulse/releases"
echo ""
echo "After publishing, update the Homebrew cask SHA256:"
echo "  sha256 \"$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')\""
