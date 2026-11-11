#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
mkdir -p "$ROOT/.build/linux-core"
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Wpedantic "$ROOT/linux/tests/core_test.cpp" -o "$ROOT/.build/linux-core/core-test"
"$ROOT/.build/linux-core/core-test"
python3 "$ROOT/linux/scripts/test-install.py"
