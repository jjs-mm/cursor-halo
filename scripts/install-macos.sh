#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
DEST_PARENT="/Applications"
if [[ "${1:-}" == "--user" ]]; then DEST_PARENT="$HOME/Applications"; shift; fi
if [[ $# -gt 1 ]]; then
    printf 'Usage: %s [--user] [path-to-Cursor-Halo.app]\n' "$0" >&2
    exit 2
fi
if [[ $# -eq 1 ]]; then
    SOURCE="$1"
elif [[ -d "$SCRIPT_DIR/Cursor Halo.app" ]]; then
    SOURCE="$SCRIPT_DIR/Cursor Halo.app"
else
    SOURCE="$SCRIPT_DIR/../dist/Cursor Halo.app"
fi
SOURCE="$(cd -- "$SOURCE" && pwd -P)"
DESTINATION="$DEST_PARENT/Cursor Halo.app"
EXPECTED_ID="local.personal.CursorHalo"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE/Contents/Info.plist")
[[ "$BUNDLE_ID" == "$EXPECTED_ID" ]] || { printf 'Source is not Cursor Halo.\n' >&2; exit 1; }
/usr/bin/codesign --verify --strict "$SOURCE"
if /usr/bin/pgrep -x CursorHalo >/dev/null; then
    printf 'Quit Cursor Halo before installing this update.\n' >&2
    exit 1
fi
mkdir -p "$DEST_PARENT"
if [[ -L "$DESTINATION" ]]; then
    printf 'Refusing to replace a symbolic link at %s\n' "$DESTINATION" >&2
    exit 1
fi
if [[ -e "$DESTINATION" ]]; then
    INSTALLED_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DESTINATION/Contents/Info.plist")
    [[ "$INSTALLED_ID" == "$EXPECTED_ID" ]] || { printf 'The destination belongs to another app.\n' >&2; exit 1; }
fi

STAGING="$(mktemp -d "$DEST_PARENT/.cursor-halo-install.XXXXXX")"
BACKUP=""
PLACED=false
finish() {
    RESULT=$?
    trap - EXIT
    if [[ "$RESULT" -ne 0 ]]; then
        if "$PLACED" && [[ -d "$DESTINATION" ]]; then
            mv "$DESTINATION" "$STAGING/failed.app"
        fi
        if [[ -n "$BACKUP" && -d "$BACKUP" && ! -e "$DESTINATION" ]]; then
            mv "$BACKUP" "$DESTINATION"
        fi
    fi
    rm -rf -- "$STAGING"
    exit "$RESULT"
}
trap finish EXIT

/usr/bin/ditto "$SOURCE" "$STAGING/Cursor Halo.app"
/usr/bin/codesign --verify --strict "$STAGING/Cursor Halo.app"
if [[ -d "$DESTINATION" ]]; then
    BACKUP="$DEST_PARENT/Cursor Halo.backup-$(date +%Y%m%d-%H%M%S)-$$.app"
    mv "$DESTINATION" "$BACKUP"
fi
mv "$STAGING/Cursor Halo.app" "$DESTINATION"
PLACED=true
/usr/bin/codesign --verify --strict "$DESTINATION"
printf 'Installed: %s\n' "$DESTINATION"
if [[ -n "$BACKUP" ]]; then
    printf 'Previous build preserved: %s\n' "$BACKUP"
    printf 'To roll back, quit Cursor Halo, move the new app aside, and rename the backup to Cursor Halo.app.\n'
fi
printf 'Launch-at-login settings were not changed.\n'
