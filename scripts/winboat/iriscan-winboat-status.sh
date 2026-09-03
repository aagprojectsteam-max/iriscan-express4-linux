#!/usr/bin/env bash
set -Eeuo pipefail
SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source "$SELF_DIR/lib.sh"
wb_parse_common_args "$@" || { echo "Usage: $0 [--compose FILE]"; exit 0; }
compose=$(wb_find_compose)
echo "COMPOSE=$compose"
if wb_has_scanner; then echo 'SCANNER_USB=PRESENT'; else echo 'SCANNER_USB=NOT_FOUND'; fi
if wb_has_usb_mount "$compose"; then echo 'USB_BUS_EXPOSURE=PRESENT'; else echo 'USB_BUS_EXPOSURE=ABSENT'; fi
python3 "$(wb_helper)" inspect "$compose"
cid=$(wb_compose_container_id "$compose")
if [[ -n "$cid" ]]; then echo 'WINBOAT_CONTAINER=RUNNING'; else echo 'WINBOAT_CONTAINER=NOT_RUNNING_OR_UNAVAILABLE'; fi
