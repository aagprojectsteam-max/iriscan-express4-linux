#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
VERSION=0.2.0
OUT=${1:-$ROOT/dist}
STAGE=$(mktemp -d)
trap 'rm -rf -- "$STAGE"' EXIT
TOOLS=iriscan-express4-winboat-tools-$VERSION
mkdir -p "$STAGE/$TOOLS/scripts/winboat" "$STAGE/$TOOLS/tools" "$STAGE/$TOOLS/docs"
cp "$ROOT"/scripts/winboat/*.sh "$STAGE/$TOOLS/scripts/winboat/"
cp "$ROOT/tools/winboat-compose-edit.py" "$STAGE/$TOOLS/tools/"
cp "$ROOT/docs/WINBOAT.md" "$ROOT/docs/WINDOWS-SETUP.md" "$ROOT/LICENSE" "$STAGE/$TOOLS/docs/"
mkdir -p "$OUT"
tar -C "$STAGE" -czf "$OUT/$TOOLS.tar.gz" "$TOOLS"
(
    cd "$STAGE"
    zip -qr "$OUT/$TOOLS.zip" "$TOOLS"
)
bash "$ROOT/scripts/build-deb.sh" "$OUT"
checksums=$OUT/IRIScan-Express4-v${VERSION}-SHA256SUMS.txt
(
    cd "$OUT"
    sha256sum "$TOOLS.tar.gz" "$TOOLS.zip" \
        "iriscan-express4-winboat-support_${VERSION}_all.deb"
) > "$checksums"
echo "RELEASE_ASSETS=$OUT"
echo "CHECKSUMS=$checksums"
