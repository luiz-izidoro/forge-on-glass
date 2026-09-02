#!/bin/sh
# Native arm64e is the single canonical release profile; arm64 is legacy rollback.
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
exec env ISB_ARCH=arm64e sh "$SCRIPT_DIR/acceptance-suite-arm64e.sh" "$@"
