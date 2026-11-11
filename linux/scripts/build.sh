#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
[[ "$(uname -s)" == Linux ]] || { printf 'Build the Linux app on Linux.\n' >&2; exit 1; }
case "$(uname -m)" in
  x86_64) ARCH=x64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) printf 'Unsupported Linux architecture.\n' >&2; exit 1 ;;
esac
BUILD="$ROOT/.build/linux-$ARCH"
cmake -S "$ROOT/linux" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD" --parallel 2
ctest --test-dir "$BUILD" --output-on-failure
printf 'Built: %s\n' "$BUILD/cursor-halo"
