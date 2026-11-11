#!/bin/bash
set -euo pipefail
[[ -f /.dockerenv ]] || { printf 'This helper must run inside its disposable Docker container.\n' >&2; exit 2; }
EXPECTED_MAJOR="${1:?Expected GNOME Shell major required}"
OUTPUT="${2:-/output}"
[[ "$EXPECTED_MAJOR" =~ ^[0-9]+$ ]] || { printf 'Invalid expected Shell version.\n' >&2; exit 2; }
mkdir -p "$OUTPUT"
python3 linux/scripts/record-gnome-environment.py "$EXPECTED_MAJOR" "$OUTPUT/environment.json"
# This image has no systemd/logind. An empty seats marker would mislead Mutter
# into requiring that absent service. Never run this helper on the host.
if [[ -d /run/systemd/seats ]]; then rmdir /run/systemd/seats; fi
mkdir -p /run/dbus
dbus-daemon --system --fork --nopidfile
node --version
node --test linux/gnome/tests/model.test.js
./linux/gnome/tests/smoke.sh "$OUTPUT"
