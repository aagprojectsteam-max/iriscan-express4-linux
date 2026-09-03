#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd -P)

# Reconstruct the sanitized initialization transcript from GitHub-sized parts
# and validate its required markers before building.
bash "$ROOT/scripts/materialize-protocol.sh"

bash "$ROOT/scripts/build.sh"
while IFS= read -r -d '' f; do bash -n "$f"; done < <(
  find "$ROOT/scripts" "$ROOT/tools" "$ROOT/tests" -type f -name '*.sh' -print0
)
python3 -m py_compile "$ROOT/tools/lineplanar_raw_to_png.py"
python3 -m py_compile "$ROOT/tools/winboat-compose-edit.py"
python3 -m py_compile "$ROOT/tools/download-winboat.py"
python3 -m py_compile "$ROOT/tests/test-download-winboat.py"
python3 "$ROOT/tests/test-download-winboat.py"

test -s "$ROOT/build/protocol/init.ops"
grep -q 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' "$ROOT/build/protocol/init.ops"
grep -q ' - 926$' "$ROOT/build/protocol/init.ops"

bash "$ROOT/tests/test-winboat.sh"
bash "$ROOT/scripts/privacy-check.sh"
bash "$ROOT/scripts/build-deb.sh" "$ROOT/build/packages"
bash "$ROOT/tests/test-package.sh" \
  "$ROOT/build/packages/iriscan-express4-ubuntu-installer_0.3.0_all.deb"
bash "$ROOT/tests/test-end-user-lifecycle.sh" \
  "$ROOT/build/packages/iriscan-express4-ubuntu-installer_0.3.0_all.deb"
bash "$ROOT/scripts/build-release.sh" "$ROOT/build/release"
(
  cd "$ROOT/build/release"
  sha256sum -c IRIScan-Express4-v0.3.0-SHA256SUMS.txt
)

echo CHECKS=PASS
