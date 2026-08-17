#!/bin/bash
#
# Builds "UTM Snapshot Manager.app" into build/Build/Products/Release.
# Used by install.sh, make-dmg.sh and CI, so the build itself is defined once.
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="UTM Snapshot Manager"
BUILD_DIR="${BUILD_DIR:-build}"
CONFIGURATION="${CONFIGURATION:-Release}"

blue()  { printf "\033[1;34m%s\033[0m\n" "$1"; }
fail()  { printf "\033[1;31m%s\033[0m\n" "$1" >&2; exit 1; }

command -v xcodebuild >/dev/null 2>&1 || fail \
  "Xcode is required. Install it, then run: sudo xcode-select -s /Applications/Xcode.app"
command -v xcodegen >/dev/null 2>&1 || fail \
  "XcodeGen is required: brew install xcodegen"

blue "Generating app icon…"
swift Tools/MakeIcon.swift

blue "Generating Xcode project…"
xcodegen generate --quiet

blue "Building ($CONFIGURATION)…"
# Capture the compiler's exit status before anything else can clobber
# PIPESTATUS. The previous version inspected it after an intervening test,
# which happened to work but only by accident.
set +e
xcodebuild \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  ARCHS="x86_64 arm64" \
  ONLY_ACTIVE_ARCH=NO \
  build 2>&1 | grep -E "(error:|warning: .*Sources|BUILD)"
BUILD_STATUS=${PIPESTATUS[0]}
set -e

[ "$BUILD_STATUS" -eq 0 ] || fail "Build failed — nothing was produced."

PRODUCT="$BUILD_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
[ -d "$PRODUCT" ] || fail "Build reported success but produced no app bundle."

# Ad-hoc signature. Without a paid Developer ID this is the best available, and
# it is what lets the app keep its Privacy permissions across rebuilds instead
# of asking again every single time.
blue "Signing (ad-hoc)…"
codesign --force --sign - "$PRODUCT" >/dev/null 2>&1 || \
  fail "Ad-hoc signing failed."

echo "$PRODUCT"
