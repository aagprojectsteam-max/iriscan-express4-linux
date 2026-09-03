#!/usr/bin/env bash
set -Eeuo pipefail
SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source "$SELF_DIR/lib.sh"
wb_parse_common_args "$@" || { echo "Usage: $0 [--compose FILE]"; exit 0; }
compose=$(wb_find_compose)
wb_validate_compose "$compose"
echo "COMPOSE=$compose"
if wb_has_scanner; then scanner=PRESENT; else scanner=NOT_FOUND; fi
if wb_has_usb_mount "$compose"; then exposure=PRESENT; else exposure=ABSENT; fi
echo "SCANNER_USB=$scanner"
echo "USB_BUS_EXPOSURE=$exposure"
python3 "$(wb_helper)" inspect "$compose"
if [[ "$scanner" == PRESENT ]]; then echo 'PREFLIGHT=PASS'; else echo 'PREFLIGHT=PASS_WITH_SCANNER_NOT_CONNECTED'; fi
