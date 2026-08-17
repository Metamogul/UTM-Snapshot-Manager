#!/bin/bash
#
# Integration tests. Builds the app's own service layer together with a test
# driver and runs it against real qcow2 images in a temporary directory.
#
# These are deliberately not mocked: the whole point of this app is what
# qemu-img actually does to a disk, and a fake qemu-img would test the fake.
#
set -euo pipefail

cd "$(dirname "$0")/.."

green() { printf "\033[1;32m%s\033[0m\n" "$1"; }
fail()  { printf "\033[1;31m%s\033[0m\n" "$1" >&2; exit 1; }

command -v qemu-img >/dev/null 2>&1 || fail "qemu-img is required: brew install qemu"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/integration-tests"

swiftc -o "$BIN" \
  Sources/Services/*.swift \
  Sources/Model/*.swift \
  Tests/Integration/main.swift

"$BIN"
green "Integration tests passed."
