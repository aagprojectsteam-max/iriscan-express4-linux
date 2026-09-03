#!/usr/bin/env bash
set -Eeuo pipefail
SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source "$SELF_DIR/lib.sh"
wb_parse_common_args "$@" || { echo "Usage: $0 [--compose FILE] [--dry-run]"; exit 0; }
compose=$(wb_find_compose)
wb_validate_compose "$compose"
echo "COMPOSE=$compose"
wb_transform remove "$compose"
echo 'Restart WinBoat through its normal user interface to activate the change.'
