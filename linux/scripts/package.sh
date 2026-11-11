#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
case "$(uname -m)" in
  x86_64) ARCH=x64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) printf 'Unsupported Linux architecture.\n' >&2; exit 1 ;;
esac
VERSION="$(tr -d '\r\n' < "$ROOT/VERSION")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'Invalid VERSION.\n' >&2; exit 1; }
BINARY="$ROOT/.build/linux-$ARCH/cursor-halo"
[[ -x "$BINARY" ]] || { printf 'Build first with linux/scripts/build.sh.\n' >&2; exit 1; }
[[ "$("$BINARY" --version)" == "Cursor Halo $VERSION" ]] || { printf 'Binary version differs from VERSION.\n' >&2; exit 1; }
STAGE="$ROOT/dist/linux/linux-$ARCH"
mkdir -p "$ROOT/dist/linux"
if [[ -e "$STAGE" ]]; then rm -rf -- "$STAGE"; fi
mkdir -p "$STAGE/app"
cp "$BINARY" "$STAGE/app/cursor-halo"
cp "$ROOT/LICENSE" "$STAGE/app/LICENSE"
cp "$ROOT/linux/scripts/install.sh" "$STAGE/Install-CursorHalo.sh"
cp "$ROOT/linux/scripts/install.py" "$STAGE/install.py"
cp "$ROOT/linux/resources/INSTALL.md" "$STAGE/INSTALL-LINUX.md"
cp "$ROOT/LICENSE" "$ROOT/README.md" "$ROOT/CONTRIBUTING.md" "$ROOT/SECURITY.md" "$ROOT/CHANGELOG.md" "$STAGE/"
cp -R "$ROOT/docs" "$STAGE/docs"
python3 - "$STAGE" "$VERSION" "$ARCH" <<'PY'
import hashlib, json, pathlib, sys
stage, version, arch = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
binary = (stage / 'app/cursor-halo').read_bytes()
if binary[:6] != b'\x7fELF\x02\x01' or int.from_bytes(binary[18:20], 'little') != {'x64': 62, 'arm64': 183}[arch]:
    raise SystemExit('The built executable does not match the package architecture.')
manifest = {'appId': 'io.github.jjs_mm.CursorHalo', 'version': version, 'architecture': arch,
            'executableSha256': hashlib.sha256(binary).hexdigest()}
(stage / 'app/.cursor-halo-install.json').write_text(json.dumps(manifest, indent=2) + '\n')
PY
ARCHIVE="CursorHalo-$VERSION-linux-$ARCH.tar.gz"
# The archive contains regular files/directories only; execute bits are preserved.
COPYFILE_DISABLE=1 tar -czf "$ROOT/dist/$ARCHIVE" -C "$STAGE" .
(cd "$ROOT/dist" && sha256sum "$ARCHIVE" > "$ARCHIVE.sha256")
printf 'Packaged: %s\n' "$ROOT/dist/$ARCHIVE"
