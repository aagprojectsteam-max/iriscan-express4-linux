#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd -P)

# Reconstruct the sanitized initialization transcript from GitHub-sized parts
# and validate its required markers before building.
bash "$ROOT/scripts/materialize-protocol.sh"

bash "$ROOT/scripts/build.sh"
for f in "$ROOT"/scripts/*.sh "$ROOT"/tools/*.sh; do bash -n "$f"; done
python3 -m py_compile "$ROOT/tools/lineplanar_raw_to_png.py"

test -s "$ROOT/build/protocol/init.ops"
grep -q 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' "$ROOT/build/protocol/init.ops"
grep -q ' - 926$' "$ROOT/build/protocol/init.ops"

echo CHECKS=PASS
