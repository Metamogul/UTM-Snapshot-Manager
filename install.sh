#!/bin/bash
#
# Builds UTM Snapshot Manager and installs it into /Applications.
# Installs missing prerequisites (QEMU, XcodeGen) via Homebrew.
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="UTM Snapshot Manager"
BUILD_DIR="build"

blue()  { printf "\033[1;34m%s\033[0m\n" "$1"; }
green() { printf "\033[1;32m%s\033[0m\n" "$1"; }
warn()  { printf "\033[1;33m%s\033[0m\n" "$1"; }
fail()  { printf "\033[1;31m%s\033[0m\n" "$1" >&2; exit 1; }

# --- Prerequisites ----------------------------------------------------------

blue "Checking prerequisites…"

xcodebuild -version >/dev/null 2>&1 || fail \
  "Xcode is required. Install it from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app"

if ! command -v brew >/dev/null 2>&1; then
  fail "Homebrew is required. See https://brew.sh"
fi

if ! command -v qemu-img >/dev/null 2>&1; then
  warn "qemu-img is missing — installing QEMU (this takes a few minutes)…"
  brew install qemu
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  warn "XcodeGen is missing — installing…"
  brew install xcodegen
fi

# --- Build ------------------------------------------------------------------

blue "Generating app icon…"
swift Tools/MakeIcon.swift

blue "Generating Xcode project…"
xcodegen generate --quiet

blue "Building…"
# The exit status of xcodebuild, not of the grep it is piped into. Without this
# a failed compile would leave the previous build in place and get installed as
# if nothing had happened.
set -o pipefail
xcodebuild \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  build 2>&1 | grep -E "(error:|BUILD)" || {
    [ "${PIPESTATUS[0]}" -eq 0 ] || fail "Build failed — nothing was installed."
  }
[ "${PIPESTATUS[0]}" -eq 0 ] || fail "Build failed — nothing was installed."

PRODUCT="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
[ -d "$PRODUCT" ] || fail "Build failed — no app bundle was produced."

# --- Install ----------------------------------------------------------------

blue "Installing into /Applications…"
rm -rf "/Applications/$APP_NAME.app"
cp -R "$PRODUCT" /Applications/

green "Done. “$APP_NAME” is in your Applications folder."
open -a "/Applications/$APP_NAME.app"
