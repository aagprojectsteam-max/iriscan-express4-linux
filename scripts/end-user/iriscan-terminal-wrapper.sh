#!/usr/bin/env bash
set -uo pipefail
case "${1:-}" in
    setup) command=(iriscan-setup --install-winboat) ;;
    doctor) command=(iriscan-doctor) ;;
    *) echo 'Invalid launcher mode.' >&2; exit 2 ;;
esac
"${command[@]}"
rc=$?
echo
read -r -p 'Press Enter to close this window... ' _
exit "$rc"
