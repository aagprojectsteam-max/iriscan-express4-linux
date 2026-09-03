#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
INSTALL=$ROOT/scripts/winboat/iriscan-winboat-install.sh
REMOVE=$ROOT/scripts/winboat/iriscan-winboat-remove.sh
HELPER=$ROOT/tools/winboat-compose-edit.py
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
export IRISCAN_SKIP_COMPOSE_VALIDATE=1

run_case() {
    local fixture=$1 name=$2 work compose before after
    work=$TMP/$name
    mkdir -p "$work"
    cp "$fixture" "$work/compose.yml"
    compose=$work/compose.yml
    before=$(sha256sum "$compose" | cut -d' ' -f1)
    bash "$INSTALL" --compose "$compose" --dry-run >/dev/null
    [[ $(sha256sum "$compose" | cut -d' ' -f1) == "$before" ]]
    bash "$INSTALL" --compose "$compose" >/dev/null
    grep -q -- '-device usb-host,vendorid=0x0a38,productid=0x0161' "$compose"
    grep -q 'id=keep_me' "$compose"
    [[ $(grep -o 'vendorid=0x0a38' "$compose" | wc -l) -eq 1 ]]
    after=$(sha256sum "$compose" | cut -d' ' -f1)
    bash "$INSTALL" --compose "$compose" >/dev/null
    [[ $(sha256sum "$compose" | cut -d' ' -f1) == "$after" ]]
    bash "$REMOVE" --compose "$compose" --dry-run >/dev/null
    [[ $(sha256sum "$compose" | cut -d' ' -f1) == "$after" ]]
    bash "$REMOVE" --compose "$compose" >/dev/null
    ! grep -q 'vendorid=0x0a38' "$compose"
    grep -q 'id=keep_me' "$compose"
    compgen -G "$compose.iriscan-backup-*" >/dev/null
}

run_case "$ROOT/tests/fixtures/winboat/mapping/docker-compose.yml" mapping
run_case "$ROOT/tests/fixtures/winboat/list/compose.yaml" list

bad=$TMP/bad.yml
printf 'services:\n  windows:\n    environment:\n      FOO: bar\n' > "$bad"
if python3 "$HELPER" inspect "$bad" >/dev/null 2>&1; then
    echo 'expected missing ARGUMENTS fixture to fail' >&2
    exit 1
fi
duplicate=$TMP/duplicate.yml
cp "$ROOT/tests/fixtures/winboat/mapping/docker-compose.yml" "$duplicate"
python3 "$HELPER" add "$duplicate" > "$TMP/once.yml"
python3 "$HELPER" add "$TMP/once.yml" > "$TMP/twice-requested.yml"
cmp -s "$TMP/once.yml" "$TMP/twice-requested.yml"
echo 'WINBOAT_FIXTURE_TESTS=PASS'
