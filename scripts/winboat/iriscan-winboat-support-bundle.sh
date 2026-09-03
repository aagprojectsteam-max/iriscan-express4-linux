#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source "$SELF_DIR/lib.sh"
wb_parse_common_args "$@" || { echo "Usage: $0 [--compose FILE]"; exit 0; }

stamp=$(date +%Y%m%d-%H%M%S)
out=${IRISCAN_SUPPORT_OUTPUT_DIR:-${TMPDIR:-/tmp}/iriscan-winboat-support-$stamp}
mkdir -p "$out"
report=$out/report.txt
compose=''
if compose=$(wb_find_compose 2>/dev/null); then :; else compose=''; fi

redact() {
    sed -E \
        -e 's#(/home/)[^/[:space:]]+#\1USER#g' \
        -e 's#(Serial(Number)?|iSerial|ID_SERIAL(_SHORT)?)([=:[:space:]]+)[^[:space:]]+#\1\4REDACTED#gI' \
        -e 's#(PASSWORD|TOKEN|SECRET|API_KEY)([=:][[:space:]]*)[^[:space:]]+#\1\2REDACTED#gI' \
        -e 's#(gh[pousr]_[A-Za-z0-9_]+|sk-[A-Za-z0-9_-]{16,})#REDACTED_TOKEN#g'
}

{
    echo 'IRIScan Express 4 / WinBoat support bundle'
    echo "timestamp=$(date -Is)"
    echo "kernel=$(uname -srmo)"
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        echo "os=${PRETTY_NAME:-unknown}"
    fi
    echo
    echo '== scanner USB only =='
    if command -v lsusb >/dev/null 2>&1; then
        lsusb -d "$IRISCAN_USB_ID" 2>&1 || true
        echo
        echo '== USB topology (identifiers only; serials excluded) =='
        lsusb -t 2>&1 || true
    else
        echo 'lsusb unavailable'
    fi
    echo
    echo '== scanner sysfs identity =='
    local_found=0
    for d in /sys/bus/usb/devices/*; do
        [[ -r "$d/idVendor" && -r "$d/idProduct" ]] || continue
        [[ "$(tr '[:upper:]' '[:lower:]' < "$d/idVendor")" == 0a38 ]] || continue
        [[ "$(tr '[:upper:]' '[:lower:]' < "$d/idProduct")" == 0161 ]] || continue
        local_found=1
        echo "usb_node=$(basename "$d")"
        echo 'serial=REDACTED'
        echo "manufacturer=$(tr -d '\r\n' < "$d/manufacturer" 2>/dev/null || true)"
        echo "product=$(tr -d '\r\n' < "$d/product" 2>/dev/null || true)"
        for interface in "$d":*; do
            [[ -e "$interface" ]] || continue
            driver=$(basename "$(readlink -f "$interface/driver" 2>/dev/null || echo none)")
            echo "interface=$(basename "$interface") driver=$driver"
        done
        find "$d" -type d -path '*/scsi_generic/sg*' -printf 'sg=%f\n' 2>/dev/null | sort -u
        while IFS= read -r sg_name; do
            [[ -n "$sg_name" ]] || continue
            scsi=/sys/class/scsi_generic/$sg_name/device
            echo "scsi_vendor=$(tr -d '\r\n ' < "$scsi/vendor" 2>/dev/null || true)"
            echo "scsi_model=$(sed 's/[[:space:]]*$//' "$scsi/model" 2>/dev/null || true)"
            echo "scsi_revision=$(tr -d '\r\n ' < "$scsi/rev" 2>/dev/null || true)"
        done < <(find "$d" -type d -path '*/scsi_generic/sg*' -printf '%f\n' 2>/dev/null | sort -u)
    done
    [[ $local_found == 1 ]] || echo 'scanner=NOT_FOUND'
    echo
    echo '== WinBoat discovery =='
    if [[ -n "$compose" ]]; then
        echo "compose_file=$(basename "$compose")"
        echo 'compose_location=REDACTED'
        echo "compose_mode=$(stat -c '%a' "$compose" 2>/dev/null || true)"
        if wb_has_usb_mount "$compose"; then echo 'usb_bus_exposure=present'; else echo 'usb_bus_exposure=absent'; fi
        python3 "$(wb_helper)" inspect "$compose" 2>&1 || true
        echo 'qemu_iris_argument=-device usb-host,vendorid=0x0a38,productid=0x0161'
        echo
        echo '== WinBoat container state =='
        if command -v docker >/dev/null 2>&1; then
            docker compose -f "$compose" ps --format json 2>&1 || true
        else
            echo 'docker unavailable'
        fi
    else
        echo 'winboat=NOT_FOUND_OR_AMBIGUOUS'
    fi
} 2>&1 | redact | tee "$report"

cat > "$out/README.txt" <<'EOF'
This archive contains narrowly scoped IRIScan/WinBoat diagnostics.
Scanner serials, common credentials, tokens, usernames, and home paths are
redacted by default. Review report.txt before publishing it.
EOF
archive=${out}.tar.gz
tar -C "$(dirname "$out")" -czf "$archive" "$(basename "$out")"
echo "SUPPORT_BUNDLE=$archive"
echo 'Review the archive before attaching it to a public GitHub issue.'
