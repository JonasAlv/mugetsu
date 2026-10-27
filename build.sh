#!/usr/bin/env bash
# Root wrapper to build Mugetsu
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec bash "$SCRIPT_DIR/source/build.sh" "$@"
