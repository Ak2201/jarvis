#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/jarvis-app-status.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/AppStatusModel.swift \
    tests/AppStatusTests.swift -o "$TEST_DIR/app-status-tests"
"$TEST_DIR/app-status-tests"
