#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_ROOT="$PROJECT_ROOT/.build"
DIST_ROOT="$PROJECT_ROOT/dist"
APP_PATH="$DIST_ROOT/Cursor Halo.app"
STAGING_APP="$BUILD_ROOT/package/Cursor Halo.app"
ICONSET_PATH="$BUILD_ROOT/package/CursorHalo.iconset"
VERSION="$(tr -d '\r\n' < "$PROJECT_ROOT/VERSION")"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'VERSION must contain a three-part release version.\n' >&2
    exit 1
fi

UNIVERSAL=false
if [[ "${1:-}" == "--universal" ]]; then UNIVERSAL=true; shift; fi
if [[ $# -ne 0 ]]; then
    printf 'Usage: %s [--universal]\n' "$0" >&2
    exit 2
fi

mkdir -p "$BUILD_ROOT/module-cache" "$BUILD_ROOT/cache" "$BUILD_ROOT/config" "$BUILD_ROOT/security" "$DIST_ROOT"
export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/module-cache"
BUILD_OPTIONS=(
    --package-path "$PROJECT_ROOT"
    --cache-path "$BUILD_ROOT/cache"
    --config-path "$BUILD_ROOT/config"
    --security-path "$BUILD_ROOT/security"
    --manifest-cache local
    --disable-sandbox
    --disable-keychain
    --disable-netrc
    -c release
    -debug-info-format none
    -Xswiftc -module-cache-path -Xswiftc "$BUILD_ROOT/module-cache"
)

# These paths contain only generated build products.
rm -rf -- "$STAGING_APP" "$ICONSET_PATH"
mkdir -p "$STAGING_APP/Contents/MacOS" "$STAGING_APP/Contents/Resources" "$ICONSET_PATH"

if "$UNIVERSAL"; then
    BINARIES=()
    for ARCH in arm64 x86_64; do
        ARCH_OPTIONS=(--scratch-path "$BUILD_ROOT/release-$ARCH" --triple "$ARCH-apple-macosx13.0")
        swift build "${BUILD_OPTIONS[@]}" "${ARCH_OPTIONS[@]}"
        BIN_PATH="$(swift build "${BUILD_OPTIONS[@]}" "${ARCH_OPTIONS[@]}" --show-bin-path)"
        BINARIES+=("$BIN_PATH/CursorHalo")
    done
    /usr/bin/lipo -create "${BINARIES[@]}" -output "$STAGING_APP/Contents/MacOS/CursorHalo"
    /usr/bin/lipo "$STAGING_APP/Contents/MacOS/CursorHalo" -verify_arch arm64
    /usr/bin/lipo "$STAGING_APP/Contents/MacOS/CursorHalo" -verify_arch x86_64
else
    swift build "${BUILD_OPTIONS[@]}" --scratch-path "$BUILD_ROOT"
    BIN_PATH="$(swift build "${BUILD_OPTIONS[@]}" --scratch-path "$BUILD_ROOT" --show-bin-path)"
    cp "$BIN_PATH/CursorHalo" "$STAGING_APP/Contents/MacOS/CursorHalo"
fi
chmod 755 "$STAGING_APP/Contents/MacOS/CursorHalo"

swift -module-cache-path "$BUILD_ROOT/module-cache" "$PROJECT_ROOT/scripts/make-icon.swift" \
    "$ICONSET_PATH" "$STAGING_APP/Contents/Resources/CursorHalo.icns"

cat > "$STAGING_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>Cursor Halo</string>
    <key>CFBundleName</key><string>Cursor Halo</string>
    <key>CFBundleExecutable</key><string>CursorHalo</string>
    <key>CFBundleIdentifier</key><string>local.personal.CursorHalo</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>CursorHalo</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

cp "$PROJECT_ROOT/LICENSE" "$STAGING_APP/Contents/Resources/LICENSE"
plutil -lint "$STAGING_APP/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$STAGING_APP"
codesign --verify --strict --verbose=2 "$STAGING_APP"
rm -rf -- "$APP_PATH"
mv "$STAGING_APP" "$APP_PATH"
printf '\nBuilt: %s\n' "$APP_PATH"
printf 'Open it with: open "%s"\n' "$APP_PATH"
