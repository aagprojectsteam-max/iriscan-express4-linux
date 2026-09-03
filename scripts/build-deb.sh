#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
VERSION=0.2.0
OUT=${1:-$ROOT/dist}
STAGE=$(mktemp -d)
trap 'rm -rf -- "$STAGE"' EXIT
PKG=$STAGE/iriscan-express4-winboat-support
mkdir -p "$PKG/DEBIAN" "$PKG/usr/bin" "$PKG/usr/lib/iriscan-express4-winboat" \
    "$PKG/usr/share/doc/iriscan-express4-winboat-support"
cp "$ROOT/packaging/debian/control" "$PKG/DEBIAN/control"
cp "$ROOT/tools/winboat-compose-edit.py" "$PKG/usr/lib/iriscan-express4-winboat/"
cp "$ROOT/scripts/winboat/lib.sh" "$PKG/usr/lib/iriscan-express4-winboat/"
for name in preflight install status verify remove support-bundle; do
    src=$ROOT/scripts/winboat/iriscan-winboat-$name.sh
    dst=$PKG/usr/bin/iriscan-winboat-$name
    cp "$src" "$dst"
    sed -i 's#SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE\[0\]}")" && pwd -P)#SELF_DIR=${IRISCAN_WINBOAT_LIB_DIR:-/usr/lib/iriscan-express4-winboat}#' "$dst"
done
cp "$ROOT/scripts/winboat/detect-winboat.sh" "$PKG/usr/bin/iriscan-winboat-detect"
sed -i 's#SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE\[0\]}")" && pwd -P)#SELF_DIR=${IRISCAN_WINBOAT_LIB_DIR:-/usr/lib/iriscan-express4-winboat}#' "$PKG/usr/bin/iriscan-winboat-detect"
cp "$ROOT/docs/WINBOAT.md" "$ROOT/docs/WINDOWS-SETUP.md" "$ROOT/LICENSE" \
    "$PKG/usr/share/doc/iriscan-express4-winboat-support/"
chmod 0755 "$PKG/usr/bin/"* "$PKG/usr/lib/iriscan-express4-winboat/"*
find "$PKG" -type d -exec chmod 0755 {} +
find "$PKG/usr/share/doc" -type f -exec chmod 0644 {} +
mkdir -p "$OUT"
dpkg-deb --root-owner-group --build "$PKG" "$OUT/iriscan-express4-winboat-support_${VERSION}_all.deb"
echo "DEB=$OUT/iriscan-express4-winboat-support_${VERSION}_all.deb"
