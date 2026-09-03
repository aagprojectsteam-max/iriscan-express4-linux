#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd -P)

# Reconstruct the sanitized initialization transcript from GitHub-sized parts
# and validate its required markers before building.
bash "$ROOT/scripts/materialize-protocol.sh"

"$ROOT/scripts/build.sh"
for f in "$ROOT"/scripts/*.sh "$ROOT"/tools/*.sh; do bash -n "$f"; done
python3 -m py_compile "$ROOT/tools/lineplanar_raw_to_png.py"

test -s "$ROOT/protocol/init.ops"
grep -q 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' "$ROOT/protocol/init.ops"
grep -q ' - 926$' "$ROOT/protocol/init.ops"

echo CHECKS=PASS
