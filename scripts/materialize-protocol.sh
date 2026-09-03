#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
DEST="${1:-$ROOT/build/protocol}"
PARTS="$ROOT/protocol/init-parts"

mkdir -p "$DEST"
OUT="$DEST/init.ops"

EXPECTED=(
  "$PARTS/part-00.ops"
  "$PARTS/part-01.ops"
  "$PARTS/part-02a.ops"
  "$PARTS/part-03.ops"
)
for f in "${EXPECTED[@]}"; do
  [[ -f "$f" ]] || { echo "ERROR: missing init transcript part: $f" >&2; exit 1; }
done

# Refuse unreviewed extra fragments; overlap/order mistakes in a replay are unsafe.
mapfile -t FOUND < <(find "$PARTS" -maxdepth 1 -type f -name 'part-*.ops' -print | sort)
[[ ${#FOUND[@]} -eq ${#EXPECTED[@]} ]] || {
  printf 'ERROR: expected %d init parts, found %d\n' "${#EXPECTED[@]}" "${#FOUND[@]}" >&2
  printf 'Found: %s\n' "${FOUND[*]}" >&2
  exit 1
}

cat "${EXPECTED[@]}" > "$OUT"
cp "$ROOT/protocol/scan-setup-300dpi-color.ops" "$DEST/"
cp "$ROOT/protocol/next-batch.ops" "$DEST/"
cp "$ROOT/protocol/scan-finish.ops" "$DEST/"

OPS_COUNT=$(grep -Ev '^[[:space:]]*(#|$)' "$OUT" | wc -l)
[[ "$OPS_COUNT" -eq 742 ]] || {
  echo "ERROR: init operation count is $OPS_COUNT, expected 742" >&2
  exit 1
}
[[ $(grep -c 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' "$OUT") -eq 1 ]] || {
  echo "ERROR: sanitized serial placeholder must appear exactly once" >&2
  exit 1
}
grep -q ' - 183$' "$OUT"
grep -q ' - 926$' "$OUT"

# Ensure transaction numbers in the public transcript are strictly increasing.
awk '
  /^[[:space:]]*(#|$)/ { next }
  {
    tx=$NF+0
    if (seen && tx <= prev) {
      printf "ERROR: non-increasing transaction id %d after %d at line %d\n", tx, prev, NR > "/dev/stderr"
      exit 1
    }
    prev=tx; seen=1
  }
' "$OUT"

echo "INIT_TRANSCRIPT=$OUT"
echo "INIT_OPERATIONS=$OPS_COUNT"
echo "INIT_SHA256=$(sha256sum "$OUT" | awk '{print $1}')"
echo "PROTOCOL_MATERIALIZATION=PASS"
