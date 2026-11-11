#!/usr/bin/env bash
set -euo pipefail

# This starts an isolated test compositor, never the user's current session.
project_root="$(cd "$(dirname "$0")/../../.." && pwd)"
output_dir="${1:-$project_root/.build/gnome-smoke}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
export XDG_CONFIG_HOME="$test_root/config"
export XDG_DATA_HOME="$test_root/data"
export XDG_CACHE_HOME="$test_root/cache"
export XDG_RUNTIME_DIR="$test_root/runtime"
export GSETTINGS_BACKEND=keyfile
export LIBGL_ALWAYS_SOFTWARE=true
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=GNOME
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
extension_dir="$XDG_DATA_HOME/gnome-shell/extensions/cursor-halo@jjs-mm.github.io"
mkdir -p "$extension_dir"
cp "$project_root"/linux/gnome/{extension.js,prefs.js,model.js,metadata.json} "$extension_dir/"
cp -R "$project_root/linux/gnome/schemas" "$extension_dir/"
glib-compile-schemas --strict "$extension_dir/schemas"
gsettings set org.gnome.shell enabled-extensions "['cursor-halo@jjs-mm.github.io']"
gsettings set org.gnome.shell disable-user-extensions false
dbus-run-session -- python3 "$project_root/linux/gnome/tests/smoke.py" "$output_dir"
