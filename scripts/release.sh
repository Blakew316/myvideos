#!/bin/bash
#
# Builds a signed, notarized My Videos release: a DMG for downloading and a ZIP + appcast
# entry for Sparkle automatic updates.
#
# One-time setup:
#   1. A "Developer ID Application" certificate in your keychain (Xcode → Settings → Accounts
#      → Manage Certificates → + → Developer ID Application).
#   2. Store notarization credentials (use an app-specific password from account.apple.com):
#        xcrun notarytool store-credentials "MyVideosNotary" --apple-id YOU@EXAMPLE.COM --team-id D8D94SXAG6
#   3. Create the Sparkle signing key (stored in your login keychain) and copy the public key it prints:
#        scripts/release.sh --generate-keys
#      Then set in video-grabber-Info.plist:
#        SUPublicEDKey = <that public key>
#        SUFeedURL     = https://<where you host it>/appcast.xml
#
# Each release:
#   1. Bump MARKETING_VERSION / CURRENT_PROJECT_VERSION in Xcode.
#   2. scripts/release.sh
#   3. Upload everything in dist/ (the DMG, the ZIP and appcast.xml) to the SUFeedURL location.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
BUILD="$ROOT/build/release"
PROFILE="${NOTARY_PROFILE:-MyVideosNotary}"
SPARKLE_BIN="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*SourcePackages/artifacts/sparkle/Sparkle/bin" -type d 2>/dev/null | head -1)"

if [[ "${1:-}" == "--generate-keys" ]]; then
    [[ -n "$SPARKLE_BIN" ]] || { echo "Build the project in Xcode once so Sparkle's tools are downloaded."; exit 1; }
    "$SPARKLE_BIN/generate_keys"
    exit 0
fi

echo "› Archiving…"
rm -rf "$BUILD" && mkdir -p "$BUILD" "$DIST"
xcodebuild -project "$ROOT/video grabber.xcodeproj" -scheme "My Videos" -configuration Release \
    -archivePath "$BUILD/My Videos.xcarchive" archive -quiet

echo "› Exporting with Developer ID…"
xcodebuild -exportArchive -archivePath "$BUILD/My Videos.xcarchive" \
    -exportOptionsPlist "$ROOT/scripts/ExportOptions.plist" -exportPath "$BUILD/export" -quiet
APP="$BUILD/export/My Videos.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")"

echo "› Notarizing $VERSION ($BUILD_NUMBER)…"
ditto -c -k --keepParent "$APP" "$BUILD/notarize.zip"
xcrun notarytool submit "$BUILD/notarize.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"

echo "› Packaging…"
ZIP="$DIST/My-Videos-$VERSION.zip"
DMG="$DIST/My-Videos-$VERSION.dmg"
rm -f "$ZIP" "$DMG"
ditto -c -k --keepParent "$APP" "$ZIP"
STAGING="$BUILD/dmg" && rm -rf "$STAGING" && mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/" && ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "My Videos" -srcfolder "$STAGING" -ov -format UDZO "$DMG" -quiet
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

if [[ -n "$SPARKLE_BIN" ]]; then
    echo "› Updating appcast…"
    "$SPARKLE_BIN/generate_appcast" "$DIST"
else
    echo "! Sparkle tools not found — build once in Xcode, then run: generate_appcast dist/"
fi

echo "✓ Done: $DMG"
