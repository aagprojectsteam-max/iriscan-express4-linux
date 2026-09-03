#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
cd "$ROOT"
tracked=$(mktemp)
trap 'rm -f -- "$tracked"' EXIT
git ls-files -z > "$tracked"

fail=0
check_pattern() {
    local label=$1 pattern=$2
    if xargs -0 grep -nEI --binary-files=without-match "$pattern" < "$tracked"; then
        echo "PRIVACY_ERROR=$label" >&2
        fail=1
    fi
}
check_pattern 'private home path' '/home/[A-Za-z0-9._-]+'
check_pattern 'credential-shaped token' '(gh[pousr]_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|-----BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY-----)'
private_infra_pattern='(ot''zar|usb[ _-]*clone|king''ston)'
check_pattern 'unrelated private infrastructure marker' "$private_infra_pattern"

if git ls-files | grep -Ei '\.(dll|exe|msi|cab|sys)$'; then
    echo 'PRIVACY_ERROR=proprietary-binary-shaped tracked file' >&2
    fail=1
fi
if [[ -n "${IRISCAN_PRIVATE_MARKERS:-}" ]]; then
    while IFS= read -r marker; do
        [[ -n "$marker" ]] || continue
        if xargs -0 grep -nF --binary-files=without-match "$marker" < "$tracked"; then
            echo 'PRIVACY_ERROR=configured private marker' >&2
            fail=1
        fi
    done <<<"$IRISCAN_PRIVATE_MARKERS"
fi
((fail == 0)) || exit 1
echo 'PRIVACY_AUDIT=PASS'
