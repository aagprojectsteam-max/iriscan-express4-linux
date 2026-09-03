#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
DEB=${1:?usage: test-package.sh PACKAGE.deb}
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
dpkg-deb --info "$DEB" >/dev/null
dpkg-deb --contents "$DEB" >/dev/null
dpkg-deb -e "$DEB" "$TMP/control"
mapfile -t control_files < <(find "$TMP/control" -maxdepth 1 -type f -printf '%f\n' | sort)
[[ "${control_files[*]}" == control ]] || {
    echo "unexpected Debian maintainer/control files: ${control_files[*]}" >&2
    exit 1
}
dpkg-deb -x "$DEB" "$TMP/root"
lib=$TMP/root/usr/lib/iriscan-express4-winboat
detected=$(IRISCAN_WINBOAT_LIB_DIR="$lib" IRISCAN_SKIP_COMPOSE_VALIDATE=1 \
    "$TMP/root/usr/bin/iriscan-winboat-detect" \
    --compose "$ROOT/tests/fixtures/winboat/mapping/docker-compose.yml")
grep -q 'WINBOAT=FOUND' <<<"$detected"
echo 'PACKAGE_TESTS=PASS'
