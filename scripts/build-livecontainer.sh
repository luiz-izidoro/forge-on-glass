#!/bin/sh
# Canonical arm64e.v1/PAC LiveContainer wrapper.
set -e
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
exec env ISB_ARCH=arm64e ISB_LIVECONTAINER=1 ISB_UNSIGNED=1 sh "$SCRIPT_DIR/build-pure-ui.sh" "$@" --unsigned
