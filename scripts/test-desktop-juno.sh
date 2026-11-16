#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/jarvis-desktop.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/DesktopJunoLogic.swift \
    tests/DesktopJunoTests.swift -o "$TEST_DIR/desktop-juno-tests"
"$TEST_DIR/desktop-juno-tests"
