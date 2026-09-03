#!/usr/bin/env bash
set -Eeuo pipefail

IRISCAN_USB_ID='0a38:0161'
IRISCAN_QEMU_ARG='-device usb-host,vendorid=0x0a38,productid=0x0161'

wb_die() { echo "ERROR: $*" >&2; exit 1; }
wb_note() { echo "$*"; }
wb_root() { cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P; }

wb_parse_common_args() {
    WB_COMPOSE="${IRISCAN_WINBOAT_COMPOSE:-}"
    WB_DRY_RUN=false
    WB_YES=false
    while (($#)); do
        case "$1" in
            --compose) (($# >= 2)) || wb_die '--compose requires a file'; WB_COMPOSE=$2; shift 2 ;;
            --dry-run) WB_DRY_RUN=true; shift ;;
            --yes) WB_YES=true; shift ;;
            -h|--help) return 2 ;;
            *) wb_die "unknown option: $1" ;;
        esac
    done
}

wb_find_compose() {
    if [[ -n "${WB_COMPOSE:-}" ]]; then
        [[ -f "$WB_COMPOSE" ]] || wb_die "compose file not found: $WB_COMPOSE"
        readlink -f -- "$WB_COMPOSE"
        return
    fi
    local config_home=${XDG_CONFIG_HOME:-$HOME/.config}
    local candidates=(
        "$HOME/.winboat/docker-compose.yml"
        "$HOME/.winboat/compose.yml"
        "$HOME/.winboat/compose.yaml"
        "$config_home/winboat/docker-compose.yml"
        "$config_home/winboat/compose.yml"
        "$config_home/winboat/compose.yaml"
    ) found=() f
    for f in "${candidates[@]}"; do
        [[ -f "$f" ]] && found+=("$(readlink -f -- "$f")")
    done
    mapfile -t found < <(printf '%s\n' "${found[@]}" | sed '/^$/d' | sort -u)
    ((${#found[@]} == 1)) || wb_die "expected one WinBoat compose file; found ${#found[@]}. Use --compose FILE"
    printf '%s\n' "${found[0]}"
}

wb_helper() {
    local root
    root=$(wb_root)
    if [[ -n "${IRISCAN_WINBOAT_LIB_DIR:-}" && -f "$IRISCAN_WINBOAT_LIB_DIR/winboat-compose-edit.py" ]]; then
        printf '%s\n' "$IRISCAN_WINBOAT_LIB_DIR/winboat-compose-edit.py"
    elif [[ -f "$root/tools/winboat-compose-edit.py" ]]; then
        printf '%s\n' "$root/tools/winboat-compose-edit.py"
    elif [[ -f /usr/lib/iriscan-express4-winboat/winboat-compose-edit.py ]]; then
        printf '%s\n' /usr/lib/iriscan-express4-winboat/winboat-compose-edit.py
    else
        wb_die 'winboat-compose-edit.py not found'
    fi
}

wb_has_scanner() {
    if command -v lsusb >/dev/null 2>&1 && lsusb -d "$IRISCAN_USB_ID" 2>/dev/null | grep -q .; then
        return 0
    fi
    local d
    for d in /sys/bus/usb/devices/*; do
        [[ -r "$d/idVendor" && -r "$d/idProduct" ]] || continue
        [[ "$(tr '[:upper:]' '[:lower:]' < "$d/idVendor")" == 0a38 ]] || continue
        [[ "$(tr '[:upper:]' '[:lower:]' < "$d/idProduct")" == 0161 ]] || continue
        return 0
    done
    return 1
}

wb_has_usb_mount() {
    grep -Eq '^[[:space:]]*-[[:space:]]*/dev/bus/usb:/dev/bus/usb([[:space:]]|:|$)' "$1"
}

wb_validate_compose() {
    local compose=$1 helper
    helper=$(wb_helper)
    python3 "$helper" inspect "$compose" >/dev/null
    if [[ "${IRISCAN_SKIP_COMPOSE_VALIDATE:-0}" != 1 ]] && command -v docker >/dev/null 2>&1; then
        docker compose -f "$compose" config --quiet >/dev/null
    fi
}

wb_backup() {
    local compose=$1 stamp backup
    stamp=$(date +%Y%m%d-%H%M%S)
    backup="${compose}.iriscan-backup-${stamp}"
    local n=0
    while [[ -e "$backup" ]]; do n=$((n + 1)); backup="${compose}.iriscan-backup-${stamp}-${n}"; done
    cp -p -- "$compose" "$backup"
    printf '%s\n' "$backup"
}

wb_transform() {
    local action=$1 compose=$2 helper tmp
    helper=$(wb_helper)
    tmp=$(mktemp "${compose}.iriscan-next.XXXXXX")
    trap 'rm -f -- "${tmp:-}"' RETURN
    python3 "$helper" "$action" "$compose" > "$tmp"
    chmod --reference="$compose" "$tmp"
    chown --reference="$compose" "$tmp" 2>/dev/null || true
    wb_validate_compose "$tmp"
    if cmp -s -- "$compose" "$tmp"; then
        wb_note "CHANGE=NONE"
        return 0
    fi
    wb_note 'PLANNED_DIFF_BEGIN'
    diff -u --label current --label planned "$compose" "$tmp" || true
    wb_note 'PLANNED_DIFF_END'
    if [[ "$WB_DRY_RUN" == true ]]; then
        wb_note 'APPLIED=NO (dry-run)'
        return 0
    fi
    local backup
    backup=$(wb_backup "$compose")
    mv -- "$tmp" "$compose"
    trap - RETURN
    if ! wb_validate_compose "$compose"; then
        cp -p -- "$backup" "$compose"
        wb_die "validation failed; restored $backup"
    fi
    wb_note "BACKUP=$backup"
    wb_note 'APPLIED=YES'
}

wb_compose_container_id() {
    local compose=$1
    command -v docker >/dev/null 2>&1 || return 0
    docker compose -f "$compose" ps -q 2>/dev/null | head -n 1 || true
}
