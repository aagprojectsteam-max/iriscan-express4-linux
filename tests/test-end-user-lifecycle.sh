#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
DEB=${1:?usage: test-end-user-lifecycle.sh PACKAGE.deb}
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
dpkg-deb -x "$DEB" "$TMP/root"
test_home=$TMP/user-home
mkdir -p "$test_home/.winboat" "$TMP/state" "$TMP/bin"
cp "$ROOT/tests/fixtures/winboat/mapping/docker-compose.yml" "$test_home/.winboat/docker-compose.yml"
cp "$ROOT/tests/fixtures/clean-bin/lsusb" "$ROOT/tests/fixtures/clean-bin/docker" \
    "$ROOT/tests/fixtures/clean-bin/dpkg-query" "$TMP/bin/"
chmod 0755 "$TMP/bin/lsusb" "$TMP/bin/docker" "$TMP/bin/dpkg-query"
export HOME=$test_home
export XDG_STATE_HOME=$TMP/state
export PATH=$TMP/bin:/usr/bin:/bin
export IRISCAN_WINBOAT_LIB_DIR=$TMP/root/usr/lib/iriscan-express4-ubuntu
setup=$TMP/root/usr/bin/iriscan-setup
doctor=$TMP/root/usr/bin/iriscan-doctor
uninstall=$TMP/root/usr/bin/iriscan-uninstall
compose=$HOME/.winboat/docker-compose.yml

empty_home=$TMP/empty-home
mkdir -p "$empty_home"
if HOME=$empty_home XDG_STATE_HOME=$TMP/empty-state "$setup" > "$TMP/first-run.txt" 2>&1; then
    echo 'expected first run without WinBoat configuration to require setup' >&2
    exit 1
fi
grep -q '^WINBOAT=NOT_CONFIGURED$' "$TMP/first-run.txt"
grep -q '^ACTION=Run: iriscan-setup --install-winboat$' "$TMP/first-run.txt"
HOME=$empty_home XDG_STATE_HOME=$TMP/empty-state "$doctor" > "$TMP/empty-doctor.txt"
grep -q '^WINBOAT=NOT_FOUND$' "$TMP/empty-doctor.txt"
grep -q '^READY_TO_SCAN=NO$' "$TMP/empty-doctor.txt"

"$setup" --compose "$compose" --yes | grep -q 'SETUP=PASS'
[[ $(grep -o 'vendorid=0x0a38' "$compose" | wc -l) -eq 1 ]]
first=$(sha256sum "$compose" | cut -d' ' -f1)
"$setup" --compose "$compose" --yes | grep -q 'PASSTHROUGH=ALREADY_CONFIGURED'
[[ $(sha256sum "$compose" | cut -d' ' -f1) == "$first" ]]

IRISCAN_TEST_CONTAINER_RUNNING=1 "$doctor" --compose "$compose" > "$TMP/doctor.txt"
grep -q '^SCANNER_FOUND=YES$' "$TMP/doctor.txt"
grep -q '^USB_ACCESS=PASS$' "$TMP/doctor.txt"
grep -q '^BACKEND=WINBOAT_OFFICIAL_WINDOWS_DRIVER$' "$TMP/doctor.txt"
grep -q '^WINBOAT=FOUND$' "$TMP/doctor.txt"
grep -q '^WINDOWS_PASSTHROUGH=CONFIGURED$' "$TMP/doctor.txt"
grep -q '^READY_TO_SCAN=YES$' "$TMP/doctor.txt"

"$uninstall" --compose "$compose" --yes | grep -q 'UNINSTALL=PASS'
! grep -q 'vendorid=0x0a38' "$compose"
"$uninstall" --compose "$compose" --yes | grep -q 'UNINSTALL=PASS'
"$setup" --compose "$compose" --yes | grep -q 'SETUP=PASS'
[[ $(grep -o 'vendorid=0x0a38' "$compose" | wc -l) -eq 1 ]]
compgen -G "$compose.iriscan-backup-*" >/dev/null
compgen -G "$XDG_STATE_HOME/iriscan-express4/setup-*.log" >/dev/null
compgen -G "$XDG_STATE_HOME/iriscan-express4/uninstall-*.log" >/dev/null
echo 'END_USER_LIFECYCLE_TEST=PASS'
