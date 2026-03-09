#!/bin/zsh
set -euo pipefail

#
# release.sh — Build, package, and publish a release.
#
# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 1.0.0
#
# Prerequisites:
#   1. GitHub CLI authenticated: gh auth login
#
# Note: App is distributed unsigned. Users must right-click > Open
# on first launch to bypass Gatekeeper.
#

# --- Configuration ---
SCHEME="KillOfficeUpdateApp"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$PROJECT_DIR/KillOfficeUpdateApp/KillOfficeUpdateApp.xcodeproj"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="KillOfficeUpdateApp"

# --- Parse args ---
VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 1.0.0"
    exit 1
fi

DMG_NAME="${APP_NAME}-v${VERSION}.dmg"
DMG_PATH="$PROJECT_DIR/$DMG_NAME"

echo "==> Releasing $APP_NAME v$VERSION"
echo ""

# --- Step 1: Validate ---
echo "--- Step 1/6: Validate ---"
if [[ -n "$(git -C "$PROJECT_DIR" status --porcelain)" ]]; then
    echo "ERROR: Working tree has uncommitted changes. Commit or stash first."
    exit 1
fi
echo "Working tree clean."

# --- Step 2: Test ---
echo ""
echo "--- Step 2/6: Run tests ---"
xcodebuild test \
    -project "$PROJECT" \
    -scheme "${SCHEME}Tests" \
    -destination 'platform=macOS' \
    -quiet 2>&1
echo "All tests passed."

# --- Step 3: Build ---
echo ""
echo "--- Step 3/6: Build release ---"
rm -rf "$BUILD_DIR"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -quiet 2>&1
APP_PATH="$BUILD_DIR/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "ERROR: Build failed — $APP_PATH not found."
    exit 1
fi
echo "Build succeeded: $APP_PATH"

# --- Step 4: Create DMG ---
echo ""
echo "--- Step 4/6: Create DMG ---"
STAGING_DIR=$(mktemp -d)
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "KillOfficeUpdate" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "$DMG_PATH" \
    -quiet

rm -rf "$STAGING_DIR"
echo "DMG created: $DMG_PATH"

# --- Step 5: Git tag ---
echo ""
echo "--- Step 5/6: Tag ---"
git -C "$PROJECT_DIR" tag "v${VERSION}"
git -C "$PROJECT_DIR" push origin "v${VERSION}"
echo "Tagged v${VERSION} and pushed."

# --- Step 6: GitHub Release ---
echo ""
echo "--- Step 6/6: Publish GitHub Release ---"
gh release create "v${VERSION}" "$DMG_PATH" \
    --title "v${VERSION}" \
    --generate-notes \
    --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)"
echo ""
echo "==> Released $APP_NAME v$VERSION (unsigned)"
echo "    DMG: $DMG_PATH"
echo "    URL: $(gh release view "v${VERSION}" --json url -q .url)"
echo ""
echo "Note: Users must right-click > Open on first launch to bypass Gatekeeper."
