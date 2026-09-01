#!/bin/sh
# LiveContainer compatibility build: arm64 guest, no guest BGTaskScheduler.
set -e
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
exec env ISB_ARCH=arm64 ISB_LIVECONTAINER=1 ISB_UNSIGNED=1 \
  sh "$SCRIPT_DIR/build-pure-ui.sh" "$@" --unsigned
