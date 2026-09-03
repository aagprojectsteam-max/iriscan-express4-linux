#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
if [[ -n "${IRISCAN_WINBOAT_LIB_DIR:-}" ]]; then LIB_DIR=$IRISCAN_WINBOAT_LIB_DIR
elif [[ -f "$SELF_DIR/../winboat/lib.sh" ]]; then LIB_DIR=$(cd -- "$SELF_DIR/../winboat" && pwd -P)
else LIB_DIR=/usr/lib/iriscan-express4-ubuntu; fi
source "$LIB_DIR/lib.sh"

WB_COMPOSE=''
WB_DRY_RUN=false
yes=false
while (($#)); do
    case "$1" in
        --compose) (($# >= 2)) || wb_die '--compose requires a file'; WB_COMPOSE=$2; shift 2 ;;
        --dry-run) WB_DRY_RUN=true; shift ;;
        --yes) yes=true; shift ;;
        -h|--help) echo "Usage: iriscan-uninstall [--dry-run] [--yes] [--compose FILE]"; exit 0 ;;
        *) wb_die "unknown option: $1" ;;
    esac
done
[[ $EUID -ne 0 ]] || wb_die 'run iriscan-uninstall as your normal desktop user, not with sudo'
state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/iriscan-express4
mkdir -p "$state_dir"
log=$state_dir/uninstall-$(date +%Y%m%d-%H%M%S).log
exec > >(tee -a "$log") 2>&1
echo "LOG=$log"
if ! compose=$(wb_find_compose 2>/dev/null); then
    echo 'UNINSTALL=NOTHING_TO_DO (WinBoat configuration not found)'
    exit 0
fi
cid=$(wb_compose_container_id "$compose")
[[ -z "$cid" ]] || wb_die 'WinBoat is running. Shut it down normally, then rerun iriscan-uninstall.'
if [[ "$WB_DRY_RUN" != true && "$yes" != true ]]; then
    WB_DRY_RUN=true
    wb_transform remove "$compose"
    read -r -p 'Remove only the IRIScan passthrough argument? [y/N] ' answer
    [[ "$answer" == y || "$answer" == Y ]] || wb_die 'cancelled'
    WB_DRY_RUN=false
fi
wb_transform remove "$compose"
echo 'UNINSTALL=PASS'
echo 'The package remains installed. Remove it with: sudo apt remove iriscan-express4-ubuntu-installer'
