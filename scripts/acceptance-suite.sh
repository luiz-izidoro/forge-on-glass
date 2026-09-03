#!/bin/sh
# Canonical arm64e.v1/PAC profile only.
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
exec env ISB_ARCH=arm64e sh "$SCRIPT_DIR/acceptance-suite-arm64e.sh" "$@"
