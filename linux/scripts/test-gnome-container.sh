#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
DISTRO="${1:?Usage: test-gnome-container.sh <Ubuntu release> <output directory>}"
OUTPUT="${2:?Output directory required}"
case "${3:-$(uname -m)}" in
  x64|x86_64) EXPECTED_ARCH=x86_64 ;;
  arm64|aarch64) EXPECTED_ARCH=aarch64 ;;
  *) printf 'GNOME compatibility checks support x64 or ARM64 hosts.\n' >&2; exit 2 ;;
esac
IMAGE_CONFIG=()
while IFS= read -r config_line; do IMAGE_CONFIG+=("$config_line"); done < <(python3 - "$ROOT/linux/containers/gnome-images.json" "$DISTRO" <<'PY'
import json, pathlib, re, sys
config = json.loads(pathlib.Path(sys.argv[1]).read_text())
try:
    selected = config[sys.argv[2]]
except KeyError:
    raise SystemExit('This Ubuntu release is not in the validated image matrix.')
if not re.fullmatch(r'ubuntu:[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}', selected['image']):
    raise SystemExit('The GNOME test image must use an immutable manifest digest.')
if not re.fullmatch(r'[0-9]+', selected['shellMajor']):
    raise SystemExit('Invalid expected GNOME Shell version.')
print(selected['image'])
print(selected['shellMajor'])
PY
)
[[ "${#IMAGE_CONFIG[@]}" -eq 2 ]] || { printf 'Could not resolve test image configuration.\n' >&2; exit 1; }
BASE_IMAGE="${IMAGE_CONFIG[0]}"
EXPECTED_MAJOR="${IMAGE_CONFIG[1]}"
mkdir -p "$OUTPUT"
OUTPUT="$(cd -- "$OUTPUT" && pwd)"
IMAGE_TAG="cursor-halo-gnome-test:ubuntu-$DISTRO"
docker build --pull --file "$ROOT/linux/containers/gnome.Dockerfile" --build-arg "BASE_IMAGE=$BASE_IMAGE" --tag "$IMAGE_TAG" "$ROOT/linux/containers"
# No host display, system bus, devices, Docker socket, or network is exposed.
# Only the test output directory is writable; the source checkout is read-only.
docker run --rm --init --network none \
  --env "CURSOR_HALO_BASE_IMAGE=$BASE_IMAGE" \
  --env "CURSOR_HALO_EXPECTED_ARCH=$EXPECTED_ARCH" \
  --mount "type=bind,source=$ROOT,target=/workspace,readonly" \
  --mount "type=bind,source=$OUTPUT,target=/output" \
  "$IMAGE_TAG" "$EXPECTED_MAJOR" /output
