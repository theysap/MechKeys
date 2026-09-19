#!/bin/bash
#
# Runs the test suite.
#
# Swift Testing's macro plugin lives in a `testing` subdirectory that the
# compiler does not search by default when building against the Command Line
# Tools, so its location is worked out here and passed in. Package.swift stays
# free of absolute paths, which would otherwise break the moment the toolchain
# moved.

set -euo pipefail

TOOLCHAIN_LIB="$(dirname "$(dirname "$(xcrun --find swift)")")/lib/swift/host/plugins"
PLUGIN_PATH="${TOOLCHAIN_LIB}/testing"

ARGS=()
if [ -d "${PLUGIN_PATH}" ]; then
    ARGS+=(-Xswiftc -plugin-path -Xswiftc "${PLUGIN_PATH}")
fi

cd "$(dirname "$0")/.."
exec swift test "${ARGS[@]}" "$@"
