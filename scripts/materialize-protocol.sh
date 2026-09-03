#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
OUT="$ROOT/protocol/init.ops"
PARTS="$ROOT/protocol/init-parts"

mapfile -t files < <(find "$PARTS" -maxdepth 1 -type f -name 'part-*.ops' -print | sort)
((${#files[@]})) || { echo "ERROR: no init transcript parts found" >&2; exit 1; }
cat "${files[@]}" > "$OUT"

# Basic integrity checks for the sanitized public transcript.
grep -q '^# AAG IRIScan Express 4 captured C5 transcript' "$OUT"
grep -q 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' "$OUT"
grep -q ' - 926$' "$OUT"

echo "INIT_TRANSCRIPT=$OUT"
echo "INIT_LINES=$(wc -l < "$OUT")"
echo "INIT_SHA256=$(sha256sum "$OUT" | awk '{print $1}')"
echo "PROTOCOL_MATERIALIZATION=PASS"
