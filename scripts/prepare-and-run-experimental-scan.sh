#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

bash "$ROOT/scripts/materialize-protocol.sh"
exec bash "$ROOT/scripts/run-experimental-scan.sh" "$@"
