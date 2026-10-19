#!/bin/bash
#
# Builds a signed, notarized My Videos release: a DMG for downloading and a ZIP + appcast
# entry for Sparkle automatic updates. The DMG and ZIP are published as a GitHub Release;
# docs/appcast.xml (served by GitHub Pages) tells installed copies about it.
#
# One-time setup:
#   1. A "Developer ID Application" certificate in your keychain (Xcode → Settings → Accounts
#      → Manage Certificates → + → Developer ID Application).
#   2. Store notarization credentials (use an app-specific password from account.apple.com):
#        xcrun notarytool store-credentials "MyVideosNotary" --apple-id YOU@EXAMPLE.COM --team-id D8D94SXAG6
#   3. Create the Sparkle signing key (stored in your login keychain) and copy the public key it prints:
#        scripts/release.sh --generate-keys
#      Then set SUPublicEDKey in video-grabber-Info.plist to that public key.
#      (SUFeedURL is already https://blakew316.github.io/myvideos/appcast.xml.)
#   4. GitHub CLI signed in: gh auth login
#
# Each release:
#   1. Bump Version and Build in Xcode (the Build number must increase every time).
#   2. Commit, then run: scripts/release.sh
#      It publishes the GitHub Release, then commits and pushes docs/appcast.xml.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
BUILD="$ROOT/build/release"
PROFILE="${NOTARY_PROFILE:-MyVideosNotary}"
REPO="Blakew316/myvideos"
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

[[ -n "$SPARKLE_BIN" ]] || { echo "! Sparkle tools not found — build once in Xcode first."; exit 1; }
[[ -n "$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$APP/Contents/Info.plist" 2>/dev/null)" ]] \
    || { echo "! SUPublicEDKey is empty in video-grabber-Info.plist — see one-time setup step 3."; exit 1; }

TAG="v$VERSION"
echo "› Publishing GitHub Release $TAG…"
gh release create "$TAG" "$DMG" "$ZIP" --repo "$REPO" --title "My Videos $VERSION" --generate-notes

echo "› Updating appcast…"
# generate_appcast keeps the entries already in appcast.xml and adds this version,
# pointing its download at the release asset.
APPCAST_WORK="$BUILD/appcast" && rm -rf "$APPCAST_WORK" && mkdir -p "$APPCAST_WORK"
cp "$ZIP" "$APPCAST_WORK/"
[[ -f "$ROOT/docs/appcast.xml" ]] && cp "$ROOT/docs/appcast.xml" "$APPCAST_WORK/"
"$SPARKLE_BIN/generate_appcast" "$APPCAST_WORK" \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    --link "https://blakew316.github.io/myvideos/"
cp "$APPCAST_WORK/appcast.xml" "$ROOT/docs/appcast.xml"
git -C "$ROOT" add docs/appcast.xml
git -C "$ROOT" commit -m "Release $VERSION ($BUILD_NUMBER)"
git -C "$ROOT" push

echo "✓ Released My Videos $VERSION — https://github.com/$REPO/releases/tag/$TAG"
