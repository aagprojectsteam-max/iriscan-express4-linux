#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
VID=0a38
PID=0161
STAMP=$(date +%Y%m%d-%H%M%S)
OUT="${TMPDIR:-/tmp}/iriscan-express4-diagnostic-$STAMP"
mkdir -p "$OUT"
REPORT="$OUT/report.txt"
redact_serial() { sed -E 's/(Serial(Number)?|iSerial|ID_SERIAL(_SHORT)?)[=: ]+[^ ]+/# SERIAL REDACTED/gI'; }
{
  echo "IRIScan Express 4 Linux diagnostic"
  echo "timestamp=$(date -Is)"
  echo "kernel=$(uname -srmo)"
  if [[ -r /etc/os-release ]]; then . /etc/os-release; echo "os=${PRETTY_NAME:-unknown}"; fi
  echo
  echo "== lsusb =="
  lsusb -d "$VID:$PID" || true
  echo
  echo "== usb tree =="
  lsusb -t || true
  echo
  USB_SYS=''
  while IFS= read -r d; do
    [[ -r "$d/idVendor" && -r "$d/idProduct" ]] || continue
    [[ "$(tr A-F a-f < "$d/idVendor")" == "$VID" ]] || continue
    [[ "$(tr A-F a-f < "$d/idProduct")" == "$PID" ]] || continue
    USB_SYS="$(readlink -f "$d")"; break
  done < <(find /sys/bus/usb/devices -mindepth 1 -maxdepth 1 \( -type d -o -type l \) | sort)
  echo "usb_sys=${USB_SYS:-NOT_FOUND}"
  if [[ -n "$USB_SYS" ]]; then
    echo "manufacturer=$(sed 's/[[:space:]]*$//' "$USB_SYS/manufacturer" 2>/dev/null || true)"
    echo "product=$(sed 's/[[:space:]]*$//' "$USB_SYS/product" 2>/dev/null || true)"
    echo "serial=REDACTED"
    echo
    echo "== interfaces/drivers =="
    for i in "$USB_SYS":*; do
      [[ -e "$i" ]] || continue
      echo "interface=$(basename "$i") class=$(cat "$i/bInterfaceClass" 2>/dev/null || true) subclass=$(cat "$i/bInterfaceSubClass" 2>/dev/null || true) protocol=$(cat "$i/bInterfaceProtocol" 2>/dev/null || true) driver=$(basename "$(readlink -f "$i/driver" 2>/dev/null || echo none)")"
    done
    echo
    echo "== scsi generic =="
    find "$USB_SYS" -type d -path '*/scsi_generic/sg*' -printf '%f\n' 2>/dev/null | sort -u || true
    echo
    echo "== block =="
    find "$USB_SYS" -type d -path '*/block/*' -printf '%f\n' 2>/dev/null | sort -u || true
  fi
  echo
  echo "== scanimage =="
  command -v scanimage >/dev/null && scanimage -L 2>&1 || echo "scanimage not installed"
  echo
  echo "== sg utilities =="
  command -v sg_inq || true
} 2>&1 | redact_serial | tee "$REPORT"
cp "$REPORT" "$OUT/README.txt"
tar -C "$(dirname "$OUT")" -czf "$OUT.tar.gz" "$(basename "$OUT")"
echo
echo "Support bundle: $OUT.tar.gz"
echo "Review it before attaching to a public issue."
