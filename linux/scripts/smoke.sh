#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
BINARY="${1:?Usage: smoke.sh <cursor-halo> <output-directory>}"
OUTPUT="${2:?Output directory required}"
mkdir -p "$OUTPUT"
BINARY="$(realpath "$BINARY")"
OUTPUT="$(realpath "$OUTPUT")"
if [[ "${3:-}" != --session ]]; then
  exec xvfb-run -a -s '-screen 0 1280x800x24' dbus-run-session -- "$ROOT/linux/scripts/smoke.sh" "$BINARY" "$OUTPUT" --session
fi
export GDK_BACKEND=x11
export XDG_SESSION_TYPE=x11
unset WAYLAND_DISPLAY
TEST_ROOT="$(mktemp -d)"
export XDG_CONFIG_HOME="$TEST_ROOT/config"
export XDG_DATA_HOME="$TEST_ROOT/data"
export XDG_CACHE_HOME="$TEST_ROOT/cache"
export XDG_RUNTIME_DIR="$TEST_ROOT/runtime"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
openbox --sm-disable > "$OUTPUT/openbox.log" 2>&1 &
WM_PID=$!
xcompmgr -a > "$OUTPUT/compositor.log" 2>&1 &
COMPOSITOR_PID=$!
cleanup() {
  kill "$WM_PID" "$COMPOSITOR_PID" 2>/dev/null || true
  wait "$WM_PID" "$COMPOSITOR_PID" 2>/dev/null || true
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT
sleep 1
kill -0 "$WM_PID" "$COMPOSITOR_PID"
timeout 45 "$BINARY" --smoke-test "$OUTPUT/native-smoke.json"
python3 - "$OUTPUT/native-smoke.json" <<'PY'
import json, pathlib, sys
result = json.loads(pathlib.Path(sys.argv[1]).read_text())
if result.get('success') is not True:
    raise SystemExit('Native Linux smoke checks failed: ' + str(result))
print(json.dumps(result, indent=2))
PY
python3 "$ROOT/linux/scripts/cli-smoke.py" "$BINARY" "$OUTPUT"
