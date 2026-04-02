#!/bin/bash
set -euo pipefail

# ScreenPilot Release Build Script
# Signs with Developer ID, notarizes, and creates a DMG

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/ScreenPilot.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG_PATH="$BUILD_DIR/ScreenPilot.dmg"
APP_NAME="ScreenPilot"
TEAM_ID="HN2BGT46R6"
SIGNING_IDENTITY="Developer ID Application: Elan Dekel ($TEAM_ID)"

echo "=== ScreenPilot Release Build ==="
echo ""

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$EXPORT_DIR"

# Step 1: Archive
echo "📦 Archiving..."
xcodebuild archive \
    -project "$PROJECT_DIR/ScreenPilot.xcodeproj" \
    -scheme ScreenPilot \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    ENABLE_HARDENED_RUNTIME=YES \
    2>&1 | tail -5

echo "✅ Archive complete"

# Step 2: Export
echo ""
echo "📤 Exporting signed app..."

cat > "$BUILD_DIR/exportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$BUILD_DIR/exportOptions.plist" \
    2>&1 | tail -5

echo "✅ Export complete"

# Step 3: Verify signing
echo ""
echo "🔍 Verifying code signature..."
APP_PATH="$EXPORT_DIR/$APP_NAME.app"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1
echo "✅ Signature valid"

# Step 4: Notarize
echo ""
echo "🔏 Submitting for notarization..."
echo "   (This may take a few minutes)"

# Create a zip for notarization
NOTARIZE_ZIP="$BUILD_DIR/ScreenPilot-notarize.zip"
ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"

# Submit for notarization using stored keychain profile
# To set up: xcrun notarytool store-credentials "ScreenPilot" --apple-id YOUR_APPLE_ID --team-id HN2BGT46R6
NOTARY_PROFILE="${NOTARY_PROFILE:-ScreenPilot}"
xcrun notarytool submit "$NOTARIZE_ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    2>&1 || {
    echo ""
    echo "⚠️  Notarization failed."
    echo "   Ensure keychain profile is set up:"
    echo "   xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id YOUR_APPLE_ID --team-id $TEAM_ID"
    echo ""
    echo "   Continuing without notarization..."
    SKIP_STAPLE=1
}

# Step 5: Staple (if notarized)
if [ "${SKIP_STAPLE:-0}" != "1" ]; then
    echo ""
    echo "📎 Stapling notarization ticket..."
    xcrun stapler staple "$APP_PATH"
    echo "✅ Stapled"
fi

# Step 6: Create DMG
echo ""
echo "💿 Creating DMG..."

# Create a temporary DMG layout directory
DMG_STAGING="$BUILD_DIR/dmg-staging"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "ScreenPilot" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH" 2>&1

# Sign the DMG too
codesign --sign "$SIGNING_IDENTITY" "$DMG_PATH"

echo "✅ DMG created"

# Done
echo ""
echo "=== Build Complete ==="
echo "📍 App:  $APP_PATH"
echo "📍 DMG:  $DMG_PATH"
echo ""
echo "Share the DMG file with others!"
