#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
if [[ -n "${IRISCAN_WINBOAT_LIB_DIR:-}" ]]; then LIB_DIR=$IRISCAN_WINBOAT_LIB_DIR
elif [[ -f "$SELF_DIR/../winboat/lib.sh" ]]; then LIB_DIR=$(cd -- "$SELF_DIR/../winboat" && pwd -P)
else LIB_DIR=/usr/lib/iriscan-express4-ubuntu; fi
source "$LIB_DIR/lib.sh"

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
fi

WB_COMPOSE=''
while (($#)); do
    case "$1" in
        --compose) (($# >= 2)) || wb_die '--compose requires a file'; WB_COMPOSE=$2; shift 2 ;;
        -h|--help) echo "Usage: iriscan-doctor [--compose FILE]"; exit 0 ;;
        *) wb_die "unknown option: $1" ;;
    esac
done

scanner=NO
usb_access=NOT_TESTED
winboat=NOT_FOUND
passthrough=NOT_CONFIGURED
container=NOT_RUNNING
ready=NO
wb_has_scanner && { scanner=YES; usb_access=PASS; }

if compose=$(wb_find_compose 2>/dev/null); then
    winboat=FOUND
    if wb_has_usb_mount "$compose"; then
        inspect=$(python3 "$(wb_helper)" inspect "$compose" 2>/dev/null || true)
        if grep -q 'IRIS_ARGUMENT_COUNT=1' <<<"$inspect"; then passthrough=CONFIGURED
        elif grep -Eq 'IRIS_ARGUMENT_COUNT=([2-9]|[1-9][0-9]+)' <<<"$inspect"; then passthrough=DUPLICATED
        fi
    else
        passthrough=USB_BUS_NOT_EXPOSED
    fi
    cid=$(wb_compose_container_id "$compose")
    [[ -n "$cid" ]] && container=RUNNING
fi

if [[ "$scanner" == YES && "$winboat" == FOUND && "$passthrough" == CONFIGURED && "$container" == RUNNING ]]; then
    ready=YES
fi

echo "SCANNER_FOUND=$scanner"
echo "OS=${PRETTY_NAME:-unknown}"
echo "ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)"
echo "USB_ACCESS=$usb_access"
echo 'BACKEND=WINBOAT_OFFICIAL_WINDOWS_DRIVER'
echo "WINBOAT=$winboat"
echo "WINDOWS_PASSTHROUGH=$passthrough"
echo "WINBOAT_CONTAINER=$container"
memory_mb=$(awk '/^MemTotal:/ {print int($2 / 1024)}' /proc/meminfo 2>/dev/null || echo 0)
home_free_gb=$(df -Pk "$HOME" | awk 'NR==2 {print int($4 / 1024 / 1024)}')
echo "RAM_MB=$memory_mb"
echo "HOME_FREE_GB=$home_free_gb"
if [[ -e /dev/kvm ]]; then echo 'KVM=PASS'; else echo 'KVM=NOT_FOUND'; fi
if command -v docker >/dev/null 2>&1; then
    echo 'DOCKER=FOUND'
    if docker compose version >/dev/null 2>&1; then echo 'DOCKER_COMPOSE=PASS'; else echo 'DOCKER_COMPOSE=NOT_FOUND'; fi
else
    echo 'DOCKER=NOT_FOUND'
    echo 'DOCKER_COMPOSE=NOT_FOUND'
fi
if command -v xfreerdp3 >/dev/null 2>&1; then echo 'FREERDP3=FOUND'; else echo 'FREERDP3=NOT_FOUND'; fi
echo 'NATIVE_LINUX=EXPERIMENTAL_NOT_INSTALLED'
echo "READY_TO_SCAN=$ready"
if [[ "$scanner" == NO ]]; then echo 'ACTION=Connect the IRIScan Express 4 USB cable.'
elif [[ "$winboat" == NOT_FOUND ]]; then echo 'ACTION=Run iriscan-setup --install-winboat.'
elif [[ "$passthrough" == DUPLICATED ]]; then echo 'ACTION=Close WinBoat, run iriscan-uninstall --yes, then run iriscan-setup.'
elif [[ "$passthrough" != CONFIGURED ]]; then echo 'ACTION=Close WinBoat and run iriscan-setup.'
elif [[ "$container" != RUNNING ]]; then echo 'ACTION=Start WinBoat, then scan in the official Windows Capture Tool.'
else echo 'ACTION=Open the official Windows Capture Tool. Windows driver status must be verified inside Windows.'
fi
