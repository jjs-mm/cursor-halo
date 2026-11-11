#!/bin/bash
set -euo pipefail
if [[ "${GITHUB_ACTIONS:-}" != "true" ]]; then
    printf 'This installation smoke check is restricted to disposable GitHub Actions runners.\n' >&2
    exit 2
fi
PROJECT_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
SOURCE="$PROJECT_ROOT/dist/Cursor Halo.app"
DESTINATION="$HOME/Applications/Cursor Halo.app"
PREFERENCES="$HOME/Library/Preferences/local.personal.CursorHalo.plist"
EXPECTED_ID="local.personal.CursorHalo"
VERSION="$(tr -d '\r\n' < "$PROJECT_ROOT/VERSION")"
shopt -s nullglob
EXISTING_BACKUPS=("$HOME/Applications"/Cursor\ Halo.backup-*.app)
if [[ -e "$DESTINATION" || -L "$DESTINATION" || ${#EXISTING_BACKUPS[@]} -ne 0 ]]; then
    printf 'Refusing to run: this runner already contains Cursor Halo installations.\n' >&2
    exit 1
fi
preference_digest() {
    if [[ -e "$PREFERENCES" ]]; then shasum -a 256 "$PREFERENCES" | cut -d ' ' -f 1
    else printf 'absent\n'; fi
}
BEFORE_PREFERENCES="$(preference_digest)"
cleanup() {
    RESULT=$?
    trap - EXIT
    # Preflight proved these app paths did not exist. Still check identity before
    # removing them so a failed test never sweeps unrelated application folders.
    OWNED=("$DESTINATION" "$HOME/Applications"/Cursor\ Halo.backup-*.app)
    for APP in "${OWNED[@]}"; do
        if [[ -d "$APP" && ! -L "$APP" ]]; then
            ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || true)
            if [[ "$ID" == "$EXPECTED_ID" ]]; then rm -rf -- "$APP"; fi
        fi
    done
    exit "$RESULT"
}
trap cleanup EXIT
verify_install() {
    APP="$1"
    /usr/bin/codesign --verify --strict "$APP"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == "$EXPECTED_ID" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]]
    test -x "$APP/Contents/MacOS/CursorHalo"
    cmp "$SOURCE/Contents/MacOS/CursorHalo" "$APP/Contents/MacOS/CursorHalo"
    cmp "$PROJECT_ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
}
"$PROJECT_ROOT/scripts/install-macos.sh" --user "$SOURCE"
verify_install "$DESTINATION"
BACKUPS=("$HOME/Applications"/Cursor\ Halo.backup-*.app)
[[ ${#BACKUPS[@]} -eq 0 ]]
"$PROJECT_ROOT/scripts/install-macos.sh" --user "$SOURCE"
verify_install "$DESTINATION"
BACKUPS=("$HOME/Applications"/Cursor\ Halo.backup-*.app)
[[ ${#BACKUPS[@]} -eq 1 ]]
verify_install "${BACKUPS[0]}"
[[ "$(preference_digest)" == "$BEFORE_PREFERENCES" ]]
printf 'Mac installer smoke passed: fresh install, replacement, backup, signatures, version, license, and unchanged preferences.\n'
printf 'The app was not launched; no login-item API was invoked.\n'
