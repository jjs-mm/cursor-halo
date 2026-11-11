#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
VERSION="$(tr -d '\r\n' < "$PROJECT_ROOT/VERSION")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'Invalid VERSION.\n' >&2; exit 1; }
APP="$PROJECT_ROOT/dist/Cursor Halo.app"
codesign --verify --strict "$APP"
/usr/bin/lipo "$APP/Contents/MacOS/CursorHalo" -verify_arch arm64
    /usr/bin/lipo "$APP/Contents/MacOS/CursorHalo" -verify_arch x86_64
STAGE="$PROJECT_ROOT/.build/archive-macos"
ARCHIVE="CursorHalo-$VERSION-macos-universal.zip"
rm -rf -- "$STAGE"
mkdir -p "$STAGE"
/usr/bin/ditto "$APP" "$STAGE/Cursor Halo.app"
cp "$PROJECT_ROOT/scripts/install-macos.sh" "$STAGE/install-macos.sh"
cp "$PROJECT_ROOT/LICENSE" "$STAGE/LICENSE"
cp "$PROJECT_ROOT/README.md" "$STAGE/README.md"
cp "$PROJECT_ROOT/CONTRIBUTING.md" "$PROJECT_ROOT/SECURITY.md" "$PROJECT_ROOT/CHANGELOG.md" "$STAGE/"
cp -R "$PROJECT_ROOT/docs" "$STAGE/docs"
# Preserve bundle files and executable modes, without local extended metadata.
/usr/bin/ditto -c -k --norsrc --noextattr --noacl "$STAGE" "$PROJECT_ROOT/dist/$ARCHIVE"
(cd "$PROJECT_ROOT/dist" && shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256")
printf 'Packaged: %s\n' "$PROJECT_ROOT/dist/$ARCHIVE"
