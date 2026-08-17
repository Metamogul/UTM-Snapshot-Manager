#!/bin/bash
#
# Builds UTM Snapshot Manager from source and installs it into /Applications.
# Installs missing prerequisites (QEMU, XcodeGen) via Homebrew.
#
#   ./install.sh
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="UTM Snapshot Manager"

blue()  { printf "\033[1;34m%s\033[0m\n" "$1"; }
green() { printf "\033[1;32m%s\033[0m\n" "$1"; }
warn()  { printf "\033[1;33m%s\033[0m\n" "$1"; }
fail()  { printf "\033[1;31m%s\033[0m\n" "$1" >&2; exit 1; }

# --- Prerequisites ----------------------------------------------------------

blue "Checking prerequisites…"

xcodebuild -version >/dev/null 2>&1 || fail \
  "Xcode is required. Install it from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app"

command -v brew >/dev/null 2>&1 || fail "Homebrew is required. See https://brew.sh"

if ! command -v qemu-img >/dev/null 2>&1; then
  warn "qemu-img is missing — installing QEMU (this takes a few minutes)…"
  brew install qemu
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  warn "XcodeGen is missing — installing…"
  brew install xcodegen
fi

if [ ! -d "/Applications/UTM.app" ]; then
  warn "UTM itself was not found in /Applications."
  warn "Snapshots will still work, but starting and stopping machines from the app will not."
fi

# --- Build ------------------------------------------------------------------

PRODUCT="$(Scripts/build-app.sh | tail -1)"
[ -d "$PRODUCT" ] || fail "Build failed — nothing was installed."

# --- Install ----------------------------------------------------------------

blue "Installing into /Applications…"
if pgrep -f "/Applications/$APP_NAME.app" >/dev/null 2>&1; then
  warn "Quitting the running copy first…"
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true

  # Wait for it to actually go. A fixed sleep is a guess, and if it guesses
  # short, `open` afterwards just brings the old instance back to the front and
  # the user believes they are running the new build.
  for _ in $(seq 1 20); do
    pgrep -f "/Applications/$APP_NAME.app" >/dev/null 2>&1 || break
    sleep 0.5
  done

  if pgrep -f "/Applications/$APP_NAME.app" >/dev/null 2>&1; then
    fail "“$APP_NAME” is still running and would not quit. Close it, then run this script again."
  fi
fi

# Stage beside the target and swap, so a copy that fails partway cannot leave
# the user with no app at all.
STAGING="/Applications/.$APP_NAME.app.new"
rm -rf "$STAGING"
cp -R "$PRODUCT" "$STAGING" || fail "Could not copy into /Applications."
rm -rf "/Applications/$APP_NAME.app"
mv "$STAGING" "/Applications/$APP_NAME.app"

green "Done. “$APP_NAME” is in your Applications folder."
echo
echo "On first launch macOS will ask for two things:"
echo "  • access to Documents/Downloads/Desktop, so your machines can be found"
echo "  • permission to control UTM, so the app can tell whether a machine is running"
echo "Both are needed; without the second one the app refuses to touch any disk."
echo

open -a "/Applications/$APP_NAME.app"
