#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export CLANG_MODULE_CACHE_PATH="$ROOT/.build/clang-module-cache"
export SWIFTPM_HOME="$ROOT/.build/swiftpm-home"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_HOME"

SWIFT_TEST_ARGS=(--disable-sandbox)

SWIFT_TESTING_FRAMEWORK_DIR="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
SWIFT_TESTING_LIB_DIR="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

if [[ -d "$SWIFT_TESTING_FRAMEWORK_DIR/Testing.framework" && -f "$SWIFT_TESTING_LIB_DIR/lib_TestingInterop.dylib" ]]; then
    SWIFT_TEST_ARGS+=(
        -Xswiftc "-F$SWIFT_TESTING_FRAMEWORK_DIR"
        -Xlinker "-F$SWIFT_TESTING_FRAMEWORK_DIR"
        -Xlinker -rpath
        -Xlinker "$SWIFT_TESTING_FRAMEWORK_DIR"
        -Xlinker -rpath
        -Xlinker "$SWIFT_TESTING_LIB_DIR"
    )
fi

(cd "$ROOT" && swift test "${SWIFT_TEST_ARGS[@]}")
