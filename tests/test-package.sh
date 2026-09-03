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
if [[ ! -d "$lib" ]]; then lib=$TMP/root/usr/lib/iriscan-express4-ubuntu; fi
detected=$(IRISCAN_WINBOAT_LIB_DIR="$lib" IRISCAN_SKIP_COMPOSE_VALIDATE=1 \
    "$TMP/root/usr/bin/iriscan-winboat-detect" \
    --compose "$ROOT/tests/fixtures/winboat/mapping/docker-compose.yml")
grep -q 'WINBOAT=FOUND' <<<"$detected"
for command in iriscan-setup iriscan-doctor iriscan-uninstall iriscan-support-bundle; do
    [[ -x "$TMP/root/usr/bin/$command" ]] || { echo "missing packaged command: $command" >&2; exit 1; }
done
for desktop in iriscan-express4-setup.desktop iriscan-express4-doctor.desktop; do
    file=$TMP/root/usr/share/applications/$desktop
    [[ -f "$file" ]] || { echo "missing desktop launcher: $desktop" >&2; exit 1; }
    grep -q '^Terminal=true$' "$file"
done
[[ -f "$TMP/root/usr/share/doc/iriscan-express4-ubuntu-installer/QUICKSTART.txt" ]]
[[ -x "$TMP/root/usr/lib/iriscan-express4-ubuntu/iriscan-terminal-wrapper.sh" ]]
echo 'PACKAGE_TESTS=PASS'
