#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "$0")" && pwd -P)
[[ $EUID -ne 0 ]] || { echo 'Run this installer as your normal desktop user, not with sudo.' >&2; exit 1; }
command -v dpkg-deb >/dev/null 2>&1 || {
    echo 'Installing the Debian package builder...'
    sudo apt update
    sudo apt install -y dpkg-dev
}
bash "$ROOT/scripts/build-deb.sh" "$ROOT/build/end-user"
deb=$ROOT/build/end-user/iriscan-express4-ubuntu-installer_0.3.0_all.deb
sudo apt install -y "$deb"
echo 'PACKAGE_INSTALL=PASS'
exec iriscan-setup "$@"
