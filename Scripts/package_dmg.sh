#!/bin/bash
set -euo pipefail

# ── Configuration ───────────────────────────────────────────────
APP_NAME="Readpic"
BUILD_DIR=".build/release"
VOLUME_NAME="Readpic"

# ── Read version from Xcode project ─────────────────────────────
VERSION=$(grep -m1 'MARKETING_VERSION' Readpic.xcodeproj/project.pbxproj | sed 's/.*= *\(.*\);/\1/')
DMG_NAME="${APP_NAME}-v${VERSION}.dmg"

# ── Locate .app ─────────────────────────────────────────────────
APP_PATH=$(find "$BUILD_DIR" -name "$APP_NAME.app" -type d | head -1)
if [ -z "$APP_PATH" ]; then
    echo "✗ $APP_NAME.app not found. Run Scripts/build.sh first."
    exit 1
fi

echo "▸ Packaging $APP_NAME.app → $DMG_NAME"

# ── Create temporary directory ──────────────────────────────────
STAGING=$(mktemp -d)
trap "rm -rf '$STAGING'" EXIT

cp -R "$APP_PATH" "$STAGING/"

# ── Create Applications symlink ─────────────────────────────────
ln -s /Applications "$STAGING/Applications"

# ── Create DMG ──────────────────────────────────────────────────
rm -f "$DMG_NAME"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG_NAME"

echo ""
echo "✓ DMG created: $DMG_NAME"
echo "  Size: $(du -sh "$DMG_NAME" | cut -f1)"
