#!/bin/bash
#
# Packages the built app into a drag-to-Applications disk image.
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="UTM Snapshot Manager"
BUILD_DIR="${BUILD_DIR:-build}"
PRODUCT="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
DIST_DIR="dist"

blue() { printf "\033[1;34m%s\033[0m\n" "$1"; }
fail() { printf "\033[1;31m%s\033[0m\n" "$1" >&2; exit 1; }

[ -d "$PRODUCT" ] || fail "No app bundle at $PRODUCT — run Scripts/build-app.sh first."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PRODUCT/Contents/Info.plist" 2>/dev/null || echo "0.0")"
DMG="$DIST_DIR/UTM-Snapshot-Manager-$VERSION.dmg"

rm -rf "$DIST_DIR/stage" "$DMG"
mkdir -p "$DIST_DIR/stage"

cp -R "$PRODUCT" "$DIST_DIR/stage/"
ln -s /Applications "$DIST_DIR/stage/Applications"

# A short note travels with the image, because an ad-hoc signed app downloaded
# from the internet is quarantined and the first launch fails with a message
# that sounds far more alarming than the situation warrants.
cat > "$DIST_DIR/stage/First launch — read me.txt" <<'EOF'
Drag "UTM Snapshot Manager" onto the Applications folder.

The app is signed ad-hoc rather than with a paid Apple Developer ID, so the
first launch needs one extra step:

  Right-click the app in Applications, choose "Open", then confirm.

Only the first launch needs this. Double-clicking works from then on.
EOF

blue "Building $DMG…"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DIST_DIR/stage" \
  -ov -format UDZO \
  "$DMG" >/dev/null

rm -rf "$DIST_DIR/stage"

shasum -a 256 "$DMG" | tee "$DMG.sha256"
blue "Done: $DMG"
