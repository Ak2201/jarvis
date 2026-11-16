#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/jarvis-ide-build.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/AppStatusModel.swift NotchBuddy/Sources/App/IDEBuildStatus.swift \
    tests/IDEBuildStatusTests.swift -o "$TEST_DIR/ide-build-tests"
"$TEST_DIR/ide-build-tests"
