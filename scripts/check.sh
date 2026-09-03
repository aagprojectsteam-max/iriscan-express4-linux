#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
"$ROOT/scripts/build.sh"
for f in "$ROOT"/scripts/*.sh "$ROOT"/tools/*.sh; do bash -n "$f"; done
python3 -m py_compile "$ROOT/tools/lineplanar_raw_to_png.py"
echo CHECKS=PASS
