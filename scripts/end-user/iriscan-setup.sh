#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
if [[ -n "${IRISCAN_WINBOAT_LIB_DIR:-}" ]]; then
    LIB_DIR=$IRISCAN_WINBOAT_LIB_DIR
elif [[ -f "$SELF_DIR/../winboat/lib.sh" ]]; then
    LIB_DIR=$(cd -- "$SELF_DIR/../winboat" && pwd -P)
else
    LIB_DIR=/usr/lib/iriscan-express4-ubuntu
fi
source "$LIB_DIR/lib.sh"

dry_run=false
yes=false
install_winboat=false
compose_arg=''
while (($#)); do
    case "$1" in
        --dry-run) dry_run=true; shift ;;
        --yes) yes=true; shift ;;
        --install-winboat) install_winboat=true; shift ;;
        --compose) (($# >= 2)) || wb_die '--compose requires a file'; compose_arg=$2; shift 2 ;;
        -h|--help)
            echo "Usage: iriscan-setup [--dry-run] [--yes] [--install-winboat] [--compose FILE]"
            exit 0 ;;
        *) wb_die "unknown option: $1" ;;
    esac
done

[[ $EUID -ne 0 ]] || wb_die 'run iriscan-setup as your normal desktop user, not with sudo'
[[ -r /etc/os-release ]] || wb_die '/etc/os-release is unavailable'
# shellcheck disable=SC1091
source /etc/os-release
case " ${ID:-} ${ID_LIKE:-} " in
    *' ubuntu '*) ;;
    *) wb_die "unsupported distribution: ${PRETTY_NAME:-unknown}; this installer targets Ubuntu" ;;
esac
arch=$(dpkg --print-architecture 2>/dev/null || uname -m)
[[ "$arch" == amd64 || "$arch" == x86_64 ]] || wb_die "WinBoat's official Debian package requires amd64; detected $arch"
ubuntu_major=${VERSION_ID%%.*}
[[ "$ubuntu_major" =~ ^[0-9]+$ ]] || wb_die "cannot parse Ubuntu version: ${VERSION_ID:-unknown}"
memory_mb=$(awk '/^MemTotal:/ {print int($2 / 1024)}' /proc/meminfo 2>/dev/null || echo 0)
home_free_gb=$(df -Pk "$HOME" | awk 'NR==2 {print int($4 / 1024 / 1024)}')

state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/iriscan-express4
mkdir -p "$state_dir"
log=$state_dir/setup-$(date +%Y%m%d-%H%M%S).log
exec > >(tee -a "$log") 2>&1
echo "IRISCAN_SETUP_VERSION=0.3.0"
echo "OS=${PRETTY_NAME:-unknown}"
echo "ARCH=$arch"
echo "RAM_MB=$memory_mb"
echo "HOME_FREE_GB=$home_free_gb"
if wb_has_scanner; then echo 'SCANNER_FOUND=YES'; else echo 'SCANNER_FOUND=NO'; fi
echo "LOG=$log"

WB_COMPOSE=$compose_arg
if ! compose=$(wb_find_compose 2>/dev/null); then
    if [[ "$install_winboat" == true ]]; then
        if command -v winboat >/dev/null 2>&1 || dpkg-query -W -f='${Status}' winboat 2>/dev/null | grep -q 'install ok installed'; then
            echo 'WINBOAT=INSTALLED_NOT_CONFIGURED'
            echo 'NEXT_STEP=Launch WinBoat, complete its Windows setup, close WinBoat, then run iriscan-setup again.'
            exit 3
        fi
        downloader=$LIB_DIR/download-winboat.py
        [[ -f "$downloader" ]] || wb_die "WinBoat downloader not found: $downloader"
        ((ubuntu_major >= 24)) || wb_die "automatic WinBoat setup requires Ubuntu 24.04 or newer for FreeRDP 3; detected ${VERSION_ID:-unknown}"
        if [[ "$dry_run" == true ]]; then
            echo 'DRY_RUN=Would install missing Docker/Compose/FreeRDP3 packages, download the latest official amd64 WinBoat .deb, verify its GitHub SHA256 digest, and invoke apt.'
            ((memory_mb >= 4096)) || echo "PREREQUISITE_WARNING=WinBoat requires at least 4096 MB RAM; detected $memory_mb MB"
            ((home_free_gb >= 32)) || echo "PREREQUISITE_WARNING=WinBoat requires at least 32 GB free storage; detected $home_free_gb GB under HOME"
            echo 'NEXT_STEP=Run again without --dry-run, then launch WinBoat and create its Windows environment.'
            exit 0
        fi
        ((memory_mb >= 4096)) || wb_die "WinBoat requires at least 4096 MB RAM; detected $memory_mb MB"
        ((home_free_gb >= 32)) || echo "PREREQUISITE_WARNING=Only $home_free_gb GB is free under HOME; select a WinBoat install location with at least 32 GB free"
        missing_packages=()
        command -v docker >/dev/null 2>&1 || missing_packages+=(docker.io)
        docker compose version >/dev/null 2>&1 || missing_packages+=(docker-compose-v2)
        command -v xfreerdp3 >/dev/null 2>&1 || missing_packages+=(freerdp3-x11)
        if ((${#missing_packages[@]})); then
            for package in "${missing_packages[@]}"; do
                apt-cache show "$package" >/dev/null 2>&1 || wb_die "Ubuntu package $package is unavailable. Follow WinBoat's official prerequisites for this Ubuntu release."
            done
            if [[ "$yes" != true ]]; then
                echo "Missing open-source prerequisites: ${missing_packages[*]}"
                read -r -p 'Install these Ubuntu packages with apt? [y/N] ' answer
                [[ "$answer" == y || "$answer" == Y ]] || wb_die 'cancelled'
            fi
            sudo apt update
            sudo apt install -y "${missing_packages[@]}"
        fi
        if [[ "$yes" != true ]]; then
            read -r -p 'Download and install the latest official WinBoat package? [y/N] ' answer
            [[ "$answer" == y || "$answer" == Y ]] || wb_die 'cancelled'
        fi
        download_dir=$(mktemp -d)
        trap 'rm -rf -- "${download_dir:-}"' EXIT
        download_result=$(python3 "$downloader" "$download_dir")
        printf '%s\n' "$download_result"
        deb=$(sed -n 's/^WINBOAT_DEB=//p' <<<"$download_result")
        [[ -f "$deb" ]] || wb_die 'verified WinBoat package was not produced'
        sudo apt install -y "$deb"
        echo 'WINBOAT_INSTALL=PASS'
        if ! id -nG | tr ' ' '\n' | grep -qx docker; then
            echo 'DOCKER_ACCESS=ACTION_REQUIRED'
            echo "Run: sudo usermod -aG docker $USER"
            echo 'Then log out and back in before launching WinBoat. The docker group grants root-equivalent access.'
        fi
        [[ -e /dev/kvm ]] || echo 'VIRTUALIZATION=NOT_DETECTED (/dev/kvm is absent; enable KVM/virtualization before running WinBoat)'
        echo 'NEXT_STEP=Launch WinBoat, complete its Windows setup, close WinBoat, then run iriscan-setup again.'
        exit 0
    fi
    echo 'WINBOAT=NOT_CONFIGURED'
    echo 'ACTION=Run: iriscan-setup --install-winboat'
    echo 'Then launch WinBoat, complete Windows setup, close it, and rerun iriscan-setup.'
    exit 3
fi

WB_COMPOSE=$compose
WB_DRY_RUN=$dry_run
WB_YES=$yes
wb_validate_compose "$compose"
wb_has_usb_mount "$compose" || wb_die 'WinBoat does not expose /dev/bus/usb; use the Docker-based WinBoat setup (Podman USB passthrough is unsupported)'
inspect=$(python3 "$(wb_helper)" inspect "$compose")
printf '%s\n' "$inspect"
argument_count=$(sed -n 's/^IRIS_ARGUMENT_COUNT=//p' <<<"$inspect")
[[ "$argument_count" != 0 && "$argument_count" != 1 ]] && wb_die 'multiple IRIS passthrough arguments exist; run iriscan-uninstall to remove them, then rerun setup'
if grep -q 'IRIS_ARGUMENT=ABSENT' <<<"$inspect"; then
    cid=$(wb_compose_container_id "$compose")
    [[ -z "$cid" ]] || wb_die 'WinBoat is running. Shut it down normally, then rerun iriscan-setup.'
    WB_DRY_RUN=true
    wb_transform add "$compose"
    if [[ "$dry_run" == true ]]; then
        echo 'SETUP=DRY_RUN_COMPLETE'
        exit 0
    fi
    if [[ "$yes" != true ]]; then
        read -r -p 'Apply exactly the displayed IRIScan USB passthrough change? [y/N] ' answer
        [[ "$answer" == y || "$answer" == Y ]] || wb_die 'cancelled'
    fi
    WB_DRY_RUN=false
    wb_transform add "$compose"
else
    echo 'PASSTHROUGH=ALREADY_CONFIGURED'
fi

echo 'SETUP=PASS'
echo 'NEXT_STEP=Start WinBoat, install the official IRIS/Avision Windows software, and scan with Capture Tool.'
echo 'DOCTOR=Run iriscan-doctor for host-side readiness.'
