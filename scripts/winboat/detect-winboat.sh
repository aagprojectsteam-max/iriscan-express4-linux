#!/usr/bin/env bash
set -Eeuo pipefail
SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=lib.sh
source "$SELF_DIR/lib.sh"
wb_parse_common_args "$@" || { echo "Usage: $0 [--compose FILE]"; exit 0; }
compose=$(wb_find_compose)
helper=$(wb_helper)
echo 'WINBOAT=FOUND'
echo "COMPOSE=$compose"
python3 "$helper" inspect "$compose"
if wb_has_usb_mount "$compose"; then echo 'USB_BUS_EXPOSURE=PRESENT'; else echo 'USB_BUS_EXPOSURE=ABSENT'; fi
