#!/bin/bash
set -euo pipefail

# ── Configuration ───────────────────────────────────────────────
PROJECT="Readpic.xcodeproj"
SCHEME="Readpic"
CONFIG="Release"
BUILD_DIR=".build/release"
APP_NAME="Readpic"

# ── Clean ───────────────────────────────────────────────────────
echo "▸ Cleaning build directory…"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ── Build ───────────────────────────────────────────────────────
echo "▸ Building $APP_NAME ($CONFIG)…"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$BUILD_DIR" \
    -skipPackagePluginValidation \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_ALLOWED=YES \
    2>&1 | tail -5

# ── Locate .app ─────────────────────────────────────────────────
APP_PATH=$(find "$BUILD_DIR" -name "$APP_NAME.app" -type d | head -1)
if [ -z "$APP_PATH" ]; then
    echo "✗ Failed to find $APP_NAME.app"
    exit 1
fi

echo "▸ Built: $APP_PATH"

# ── Ad-hoc sign ─────────────────────────────────────────────────
echo "▸ Ad-hoc signing…"
codesign --force --deep --sign - "$APP_PATH"

# ── Verify ──────────────────────────────────────────────────────
echo "▸ Verifying signature…"
codesign --verify --verbose "$APP_PATH" 2>&1 | tail -3

echo ""
echo "✓ Build complete: $APP_PATH"
echo "  Size: $(du -sh "$APP_PATH" | cut -f1)"
