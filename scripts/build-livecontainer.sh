#!/bin/sh
# Native arm64e is now the canonical output. LiveContainer must accept the
# PAC/v1 slice; select ISB_ARCH=arm64 explicitly only for legacy rollback.
set -e
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
exec env ISB_ARCH="${ISB_ARCH:-arm64e}" ISB_LIVECONTAINER=1 ISB_UNSIGNED=1 \
  sh "$SCRIPT_DIR/build-pure-ui.sh" "$@" --unsigned
