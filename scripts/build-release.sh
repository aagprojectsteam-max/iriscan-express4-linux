#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
VERSION=0.3.0
OUT=${1:-$ROOT/dist}
mkdir -p "$OUT"
bash "$ROOT/scripts/build-deb.sh" "$OUT"
cp "$ROOT/docs/QUICKSTART.txt" "$OUT/IRIScan-Express4-Ubuntu-QUICKSTART.txt"
checksums=$OUT/IRIScan-Express4-v${VERSION}-SHA256SUMS.txt
(
    cd "$OUT"
    sha256sum "iriscan-express4-ubuntu-installer_${VERSION}_all.deb" \
        IRIScan-Express4-Ubuntu-QUICKSTART.txt
) > "$checksums"
echo "RELEASE_ASSETS=$OUT"
echo "CHECKSUMS=$checksums"
