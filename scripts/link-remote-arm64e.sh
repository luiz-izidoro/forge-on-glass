#!/bin/sh
# link-remote-arm64e.sh — link Mach-O arm64e on the Linux VM using the
# upstream LLD ARM64e/PAC implementation, then return the executable.
# Usage: link-remote-arm64e.sh APP OBJDIR OUTPUT [extra-object ...]
set -e
APP="${1:?app}"; OBJDIR="${2:?objdir}"; OUTPUT="${3:?output}"
shift 3
case "$APP" in *[!A-Za-z0-9_.-]*) echo "AppName invalido" >&2; exit 2;; esac
HOST="${ISB_REMOTE_HOST:?ISB_REMOTE_HOST ausente}"
USER="${ISB_REMOTE_USER:?ISB_REMOTE_USER ausente}"
DEST="$USER@$HOST"
RSDK="${ISB_REMOTE_SDK:-/opt/isb/sysroot/iPhoneOS26.5.sdk}"
RLINK="${ISB_REMOTE_LINKER:-/opt/isb/sysroot/lld-arm64e-build/bin/lld}"
RDIR="/tmp/isb-arm64e-${APP}-$$"
RBASE="$DEST:$RDIR"
RLD="$RLINK"
cleanup() { ssh -o BatchMode=yes "$DEST" "rm -rf '$RDIR'" >/dev/null 2>&1 || true; }
trap cleanup EXIT

ssh -o BatchMode=yes "$DEST" "mkdir -p '$RDIR/obj'"
# Transfer the primary-file objects without exposing source or credentials.
tar -C "$OBJDIR" -cf - . | ssh -o BatchMode=yes "$DEST" "tar -xf - -C '$RDIR/obj'"
for f in "$@"; do
  [ -f "$f" ] || { echo "objeto extra ausente: $f" >&2; exit 1; }
  scp -q -o BatchMode=yes "$f" "$RBASE/obj/$(basename "$f")"
done

# Frameworks mínimos para o loader arm64e; extras são opt-in.
if [ "${ISB_MINIMAL_LINK:-1}" = "1" ]; then
  FWFLAGS="-framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore"
else
  FWFLAGS="-framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -framework SwiftUI -framework CoreText -framework Combine"
fi
for fw in ${ISB_REMOTE_FRAMEWORKS:-}; do
  FWFLAGS="$FWFLAGS -framework $fw"
  case "$fw" in
    NaturalLanguage) FWFLAGS="$FWFLAGS -lswiftNaturalLanguage";;
    CoreML) FWFLAGS="$FWFLAGS -lswiftCoreML";;
    Vision) FWFLAGS="$FWFLAGS -lswiftVision";;
    Accelerate) FWFLAGS="$FWFLAGS -lswiftAccelerate";;
  esac
done
ssh -o BatchMode=yes "$DEST" "set -- '$RDIR'/obj/*.o; exec '$RLD' -flavor darwin -arch arm64e -platform_version ios 26.5 26.5 -syslibroot '$RSDK' -L'$RSDK/usr/lib' -L'$RSDK/usr/lib/swift' -lSystem -lobjc -F'$RSDK/System/Library/Frameworks' $FWFLAGS -lswiftCore -lswiftFoundation -lswiftUIKit -lswiftDarwin -lswiftObjectiveC -lswiftCoreGraphics -lswiftDispatch -lswiftCoreFoundation -lswiftQuartzCore -rpath /usr/lib/swift -e _main \"\$@\" -o '$RDIR/$APP'"
scp -q -o BatchMode=yes "$RBASE/$APP" "$OUTPUT"
file "$OUTPUT" 2>/dev/null || true
