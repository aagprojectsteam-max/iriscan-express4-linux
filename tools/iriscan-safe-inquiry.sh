#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
VID=0a38; PID=0161
USB_SYS=''
while IFS= read -r d; do
  [[ -r "$d/idVendor" && -r "$d/idProduct" ]] || continue
  [[ "$(tr A-F a-f < "$d/idVendor")" == "$VID" ]] || continue
  [[ "$(tr A-F a-f < "$d/idProduct")" == "$PID" ]] || continue
  USB_SYS="$(readlink -f "$d")"; break
done < <(find /sys/bus/usb/devices -mindepth 1 -maxdepth 1 \( -type d -o -type l \) | sort)
[[ -n "$USB_SYS" ]] || { echo "IRIScan Express 4 $VID:$PID not found" >&2; exit 1; }
mapfile -t SGS < <(find "$USB_SYS" -type d -path '*/scsi_generic/sg*' -printf '%f\n' 2>/dev/null | sort -u)
[[ ${#SGS[@]} -eq 1 ]] || { echo "Expected exactly one sg node, found ${#SGS[@]}" >&2; exit 1; }
SG=/dev/${SGS[0]}
[[ -c "$SG" ]] || { echo "$SG is not a character device" >&2; exit 1; }
command -v sg_inq >/dev/null || { echo "Install sg3-utils first: sudo apt install sg3-utils" >&2; exit 2; }
SCSI=$(readlink -f "/sys/class/scsi_generic/${SGS[0]}/device")
V=$(sed 's/[[:space:]]*$//' "$SCSI/vendor" 2>/dev/null || true)
M=$(sed 's/[[:space:]]*$//' "$SCSI/model" 2>/dev/null || true)
[[ "$V" == IRIS && "$M" == IRIScanExpress4 ]] || { echo "Refusing unexpected SCSI device vendor=$V model=$M" >&2; exit 3; }
echo "Sending standard SCSI INQUIRY only to $SG ($V $M)"
exec sg_inq "$SG"
