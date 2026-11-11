#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$PROJECT_ROOT/.build/tests"
SWIFTC_PATH="$(xcrun --find swiftc)"
TOOLCHAIN_PREFIX="$(cd -- "$(dirname -- "$SWIFTC_PATH")/.." && pwd)"
SWIFT_BIN="$TOOLCHAIN_PREFIX/bin/swift"
TESTING_PLUGIN_PATH="$TOOLCHAIN_PREFIX/lib/swift/host/plugins/testing"

# Swift Testing requires Swift 6+. Keep its outputs separate from release builds
# and keep all caches inside the project, including manifest compilation caches.
mkdir -p "$TEST_ROOT/scratch" "$TEST_ROOT/cache" "$TEST_ROOT/module-cache" \
    "$TEST_ROOT/config" "$TEST_ROOT/security"
export CLANG_MODULE_CACHE_PATH="$TEST_ROOT/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$TEST_ROOT/module-cache"

TEST_OPTIONS=(
    --package-path "$PROJECT_ROOT"
    --scratch-path "$TEST_ROOT/scratch"
    --cache-path "$TEST_ROOT/cache"
    --config-path "$TEST_ROOT/config"
    --security-path "$TEST_ROOT/security"
    --manifest-cache local
    --disable-sandbox
    --disable-keychain
    --disable-netrc
    --disable-xctest
    -Xswiftc -module-cache-path -Xswiftc "$TEST_ROOT/module-cache"
)

# Some Command Line Tools releases bundle Testing's macros without adding this
# directory to SwiftPM's plugin search path. Full Xcode toolchains may not need it.
if [[ -d "$TESTING_PLUGIN_PATH" ]]; then
    TEST_OPTIONS+=(-Xswiftc -plugin-path -Xswiftc "$TESTING_PLUGIN_PATH")
fi

# Additional swift test arguments are accepted, e.g. --filter OverlayControllerTests.
"$SWIFT_BIN" test "${TEST_OPTIONS[@]}" "$@"
