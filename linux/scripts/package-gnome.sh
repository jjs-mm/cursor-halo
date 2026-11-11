#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
VERSION="$(tr -d '\r\n' < "$ROOT/VERSION")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'Invalid VERSION.\n' >&2; exit 1; }
STAGE="$ROOT/.build/archive-gnome46"
rm -rf -- "$STAGE"
mkdir -p "$STAGE/schemas" "$ROOT/dist"
cp "$ROOT/linux/gnome/metadata.json" "$ROOT/linux/gnome/extension.js" "$ROOT/linux/gnome/prefs.js" "$ROOT/linux/gnome/model.js" "$STAGE/"
cp "$ROOT/linux/gnome/schemas/"*.xml "$STAGE/schemas/"
cp "$ROOT/LICENSE" "$STAGE/LICENSE"
cp "$ROOT/linux/gnome/README.md" "$STAGE/README.md"
python3 - "$STAGE/metadata.json" "$VERSION" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
metadata = json.loads(path.read_text())
if metadata['shell-version'] != ['46']:
    raise SystemExit('This package is validated for GNOME Shell 46 only.')
metadata['version-name'] = sys.argv[2]
path.write_text(json.dumps(metadata, indent=2) + '\n')
PY
glib-compile-schemas --strict "$STAGE/schemas"
ARCHIVE="CursorHalo-$VERSION-gnome-shell-46.zip"
python3 - "$STAGE" "$ROOT/dist/$ARCHIVE" <<'PY'
import pathlib, sys, zipfile
stage, target = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as archive:
    for source in sorted(stage.rglob('*')):
        if source.is_symlink():
            raise SystemExit('Unexpected symbolic link in GNOME extension package.')
        if source.is_file():
            archive.write(source, source.relative_to(stage))
PY
(cd "$ROOT/dist" && sha256sum "$ARCHIVE" > "$ARCHIVE.sha256")
printf 'Packaged: %s\n' "$ROOT/dist/$ARCHIVE"
