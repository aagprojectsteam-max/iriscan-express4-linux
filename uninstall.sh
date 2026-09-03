#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -ne 0 ]] || { echo 'Run this uninstaller as your normal desktop user, not with sudo.' >&2; exit 1; }
if command -v iriscan-uninstall >/dev/null 2>&1; then
    iriscan-uninstall "$@"
fi
sudo apt remove -y iriscan-express4-ubuntu-installer
echo 'PACKAGE_UNINSTALL=PASS'
