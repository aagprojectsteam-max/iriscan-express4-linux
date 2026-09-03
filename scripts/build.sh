#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
mkdir -p "$ROOT/build"
gcc -std=c11 -O2 -Wall -Wextra -Wpedantic -Werror \
  "$ROOT/src/iriscan-express4-experimental.c" \
  -o "$ROOT/build/iriscan-express4-experimental"
echo "Built: $ROOT/build/iriscan-express4-experimental"
