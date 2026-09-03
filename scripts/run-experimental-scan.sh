#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

VID='0a38'
PID='0161'
EXPECTED_SERIAL="${IRISCAN_SERIAL:-}"
EXPECTED_VENDOR='IRIS'
EXPECTED_MODEL='IRIScanExpress4'
SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SRC="$SELF_DIR/../src/iriscan-express4-experimental.c"
BIN="$SELF_DIR/aag-iriscan-poc"
OPS_TEMPLATE="$SELF_DIR/../protocol"
CONVERTER="$SELF_DIR/../tools/lineplanar_raw_to_png.py"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$HOME/Downloads/IRIScan-Experimental-Scan-$STAMP"
LOG="$OUT/IRIScan-Experimental-Scan.log"

fatal() { echo "ERROR: $*" >&2; exit 1; }
trim_file() { sed 's/[[:space:]]*$//' "$1" 2>/dev/null || true; }

cat <<'EOF'
============================================================
 IRISCAN EXPRESS 4 / EXPERIMENTAL NATIVE LINUX SCAN
 Captured protocol replay over SG_IO — 300 DPI COLOR
============================================================

This is the first real Linux scan test derived from the successful
Windows USB capture. It will move the paper and scan one page.
EOF

[[ -f "$SRC" ]] || fatal "Missing source: $SRC"
[[ -d "$OPS_TEMPLATE" ]] || fatal "Missing transcript directory: $OPS_TEMPLATE"
[[ -x "$CONVERTER" ]] || fatal "Missing converter: $CONVERTER"
for f in init.ops scan-setup-300dpi-color.ops next-batch.ops scan-finish.ops; do
    [[ -f "$OPS_TEMPLATE/$f" ]] || fatal "Missing transcript: $OPS_TEMPLATE/$f"
done

if ! command -v gcc >/dev/null 2>&1; then
    echo "gcc is missing; installing build-essential..."
    sudo apt-get update
    sudo apt-get install -y build-essential
fi
[[ -r /usr/include/scsi/sg.h ]] || fatal "/usr/include/scsi/sg.h is missing"
command -v python3 >/dev/null 2>&1 || fatal "python3 is missing"

mkdir -p "$OUT"

USB_SYS=''
while IFS= read -r d; do
    [[ -r "$d/idVendor" && -r "$d/idProduct" ]] || continue
    [[ "$(tr '[:upper:]' '[:lower:]' < "$d/idVendor")" == "$VID" ]] || continue
    [[ "$(tr '[:upper:]' '[:lower:]' < "$d/idProduct")" == "$PID" ]] || continue
    if [[ -n "$EXPECTED_SERIAL" ]]; then [[ "$(trim_file "$d/serial")" == "$EXPECTED_SERIAL" ]] || continue; fi
    USB_SYS="$(readlink -f "$d")"
    break
done < <(find /sys/bus/usb/devices -mindepth 1 -maxdepth 1 \( -type l -o -type d \) | sort)
[[ -n "$USB_SYS" ]] || fatal "IRIScan $VID:$PID was not found${EXPECTED_SERIAL:+ with requested serial}"

MANUFACTURER="$(trim_file "$USB_SYS/manufacturer")"
PRODUCT="$(trim_file "$USB_SYS/product")"
[[ "$MANUFACTURER" == 'IRIS' ]] || fatal "Unexpected manufacturer: $MANUFACTURER"
[[ "$PRODUCT" == 'IRIScanExpress4' ]] || fatal "Unexpected product: $PRODUCT"

# Public transcripts intentionally do not contain a private device serial.
# Create a private runtime copy and inject this connected scanner's serial
# into the one captured SEND payload that carries a 16-byte serial field.
DEVICE_SERIAL="$(trim_file "$USB_SYS/serial")"
[[ -n "$DEVICE_SERIAL" ]] || fatal "Scanner serial is unavailable"
[[ ${#DEVICE_SERIAL} -le 16 ]] || fatal "Scanner serial is longer than the captured 16-byte field"
SERIAL_HEX="$(printf '%-16s' "$DEVICE_SERIAL" | od -An -tx1 -v | tr -d ' \n')"
OPS="$OUT/protocol-runtime"
cp -a "$OPS_TEMPLATE" "$OPS"
python3 - "$OPS/init.ops" "$SERIAL_HEX" <<'PY_SERIAL'
from pathlib import Path
import sys
p = Path(sys.argv[1])
serial_hex = sys.argv[2]
placeholder = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
text = p.read_text()
if text.count(placeholder) != 1:
    raise SystemExit("serial placeholder missing or ambiguous")
p.write_text(text.replace(placeholder, serial_hex))
PY_SERIAL

mapfile -t SG_NAMES < <(
    find "$USB_SYS" -type d -name 'sg[0-9]*' 2>/dev/null |
    awk -F/ '$(NF-1)=="scsi_generic" {print $NF}' |
    sort -u
)
[[ "${#SG_NAMES[@]}" -eq 1 ]] || fatal "Expected exactly one sg device; found ${#SG_NAMES[@]}: ${SG_NAMES[*]:-none}"
SG_NAME="${SG_NAMES[0]}"
SG_DEV="/dev/$SG_NAME"
SG_CLASS="/sys/class/scsi_generic/$SG_NAME"
[[ -c "$SG_DEV" ]] || fatal "$SG_DEV is not a character device"
SCSI_SYS="$(readlink -f "$SG_CLASS/device")"
[[ "$SCSI_SYS" == "$USB_SYS"/* ]] || fatal "$SG_DEV is not below the verified USB device"
SCSI_VENDOR="$(trim_file "$SCSI_SYS/vendor")"
SCSI_MODEL="$(trim_file "$SCSI_SYS/model")"
SCSI_REV="$(trim_file "$SCSI_SYS/rev")"
SCSI_TYPE="$(trim_file "$SCSI_SYS/type")"
[[ "$SCSI_VENDOR" == "$EXPECTED_VENDOR" ]] || fatal "Unexpected SCSI vendor: $SCSI_VENDOR"
[[ "$SCSI_MODEL" == "$EXPECTED_MODEL" ]] || fatal "Unexpected SCSI model: $SCSI_MODEL"

# Abort rather than touch the device if its block node is mounted.
mapfile -t BLOCKS < <(find "$SCSI_SYS/block" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -u)
for b in "${BLOCKS[@]:-}"; do
    [[ -n "$b" ]] || continue
    while IFS= read -r mp; do
        [[ -z "$mp" ]] || fatal "Scanner block node /dev/$b is mounted at $mp; unmount it first"
    done < <(lsblk -nrpo MOUNTPOINT "/dev/$b" 2>/dev/null | sed '/^[[:space:]]*$/d' || true)
done

echo
echo '========== VERIFIED DEVICE =========='
echo "USB_SYS=$USB_SYS"
echo "VID:PID=$VID:$PID"
echo "MANUFACTURER=$MANUFACTURER"
echo "PRODUCT=$PRODUCT"
echo "SERIAL=$(if [[ -n "$EXPECTED_SERIAL" ]]; then echo requested-match; else echo not-pinned; fi)"
echo "SG_DEV=$SG_DEV"
echo "SCSI_VENDOR=$SCSI_VENDOR"
echo "SCSI_MODEL=$SCSI_MODEL"
echo "SCSI_REV=$SCSI_REV"
echo "SCSI_TYPE=$SCSI_TYPE"
ls -l "$SG_DEV"

echo
echo '========== BUILD =========='
gcc -std=c11 -O2 -Wall -Wextra -Wpedantic -Werror "$SRC" -o "$BIN"
echo 'Compile: PASS'
file "$BIN"

echo
echo '========== READY =========='
echo 'Insert exactly one page into the IRIScan Express 4.'
echo 'The scan mode is the captured known-good mode: 300 DPI, Color.'
read -r -p 'Press Enter to begin the native Linux scan... '

sudo -v
set +e
sudo "$BIN" \
    --device "$SG_DEV" \
    --ops-dir "$OPS" \
    --output-dir "$OUT" \
    2>&1 | tee "$LOG"
RC=${PIPESTATUS[0]}
set -e

# Return ownership of generated files to the desktop user.
sudo chown -R "$(id -u):$(id -g)" "$OUT" 2>/dev/null || true

if [[ "$RC" -ne 0 ]]; then
    echo
    echo '============================================================'
    echo "SCAN TEST FAILED — exit code $RC"
    echo '============================================================'
    echo "LOG=$LOG"
    echo "OUT=$OUT"
    exit "$RC"
fi

META="$OUT/scan-metadata.json"
RAW="$OUT/IRIScan-300dpi-color-line-planar.raw"
PNG="$OUT/IRIScan-300dpi-color.png"
[[ -f "$META" && -f "$RAW" ]] || fatal 'Scanner reported success but output files are missing'
python3 "$CONVERTER" --metadata "$META" --raw "$RAW" --output "$PNG"

cat <<EOF

============================================================
 NATIVE LINUX SCAN: SUCCESS
============================================================
PNG=$PNG
PPM=$OUT/IRIScan-300dpi-color.ppm
RAW=$RAW
METADATA=$META
LOG=$LOG

NEXT_ROUTE=BUILD_SANE_BACKEND
============================================================
EOF

if command -v gio >/dev/null 2>&1; then
    gio open "$PNG" >/dev/null 2>&1 &
fi
