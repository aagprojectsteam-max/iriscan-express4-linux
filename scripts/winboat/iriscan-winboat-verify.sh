#!/usr/bin/env bash
set -Eeuo pipefail
SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source "$SELF_DIR/lib.sh"
wb_parse_common_args "$@" || { echo "Usage: $0 [--compose FILE]"; exit 0; }
compose=$(wb_find_compose)
wb_validate_compose "$compose"
wb_has_scanner || wb_die 'scanner 0a38:0161 is not connected to Ubuntu'
wb_has_usb_mount "$compose" || wb_die 'compose lacks /dev/bus/usb exposure'
inspect=$(python3 "$(wb_helper)" inspect "$compose")
grep -q 'IRIS_ARGUMENT=PRESENT' <<<"$inspect" || wb_die 'IRIS QEMU passthrough argument is absent'
printf '%s\n' "$inspect"
cid=$(wb_compose_container_id "$compose")
if [[ -n "$cid" ]]; then
    docker exec "$cid" sh -c 'test -e /dev/bus/usb' || wb_die 'running WinBoat container cannot see /dev/bus/usb'
    echo 'CONTAINER_USB_BUS=VISIBLE'
else
    echo 'CONTAINER_USB_BUS=NOT_CHECKED (WinBoat is not running or Docker is unavailable)'
fi
echo 'HOST_VERIFICATION=PASS'
echo 'WINDOWS_VERIFICATION=REQUIRED (see docs/WINDOWS-SETUP.md)'
