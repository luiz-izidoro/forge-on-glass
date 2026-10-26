#!/bin/sh
# build-pure-ui.sh — compiles and packages a 100% Swift iOS app (UIKit/SwiftUI).
# The only supported profile is arm64e/PAC; LiveContainer receives an unsigned
# arm64e guest and its post-import host compatibility is not implied.
SKILL=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$SKILL/scripts/profile.sh"
#
# Usage: ./build-pure-ui.sh <AppName> <BundleID> <main.swift> [other.swift ...]
#                         [--debug] [--primary-file | --whole-module]
# Output: /var/minis/workspace/<AppName>.ipa
# --debug: preserves get-task-allow, includes DebugSupport.swift and the DBG overlay
# --extra-objc FILE.m: compiles an Objective-C bridge against the SDK and links it
# --resources DIR: copies weights/models into the bundle (use with CoreML/Vision)
#
# COMPILATION MODE (2026-08-23):
#   --primary-file  (DEFAULT with 2+ files) compiles file-by-file via
#                   build-parallel.py and links with link-ipa.sh.
#   --whole-module  old mode (a single swift-frontend with all sources).
#
#   Why the default changed: in whole-module, a file that uses CoreGraphics
#   makes Foundation types (Bundle/NotificationCenter/OperationQueue)
#   DISAPPEAR from OTHER files in the same module:
#       error: cannot find 'Bundle' in scope
#   Deterministic and reproduced with 2 files. With -primary-file the SAME
#   code compiles in seconds, with no changes at all.
#   See references/WARNINGS-FATAIS.md -> "CoreGraphics degrades Foundation".
set -e
ISB_WORKSPACE="${ISB_WORKSPACE:-/var/minis/workspace}"
APP="${1:?usage: $0 <AppName> <BundleID> <main.swift> [other.swift ...] [--debug]}"
BUNDLE="${2:?missing the bundle id}"
shift 2
DEBUG=0
UNSIGNED="${ISB_UNSIGNED:-0}"
UNSIGNED_EXPLICIT=0
MODE=""
SRC_ARGS=""
OBJC_ARGS=""
FRAMEWORK_ARGS=""
OPT_MODE="${ISB_OPT:-O}"
case "$OPT_MODE" in
  none) OPT_FLAGS=-Onone ;;
  O) OPT_FLAGS=-O ;;
  Osize) OPT_FLAGS=-Osize ;;
  *) echo "ISB_OPT invalid: $OPT_MODE (use none, O or Osize)" >&2; exit 2 ;;
esac
SWIFT_DEFINES="${ISB_SWIFT_DEFINES:-}"
PLIST_EXTRA=""
WEAK_FRAMEWORK_ARGS=""
RESOURCES=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --debug) DEBUG=1 ;;
    --unsigned) UNSIGNED=1; UNSIGNED_EXPLICIT=1 ;;
    --primary-file) MODE=primary ;;
    --whole-module) MODE=whole ;;
    --extra-objc) OBJC_ARGS="$OBJC_ARGS $2"; shift ;;
    --extra-framework) FRAMEWORK_ARGS="$FRAMEWORK_ARGS $2"; shift ;;
    --weak-framework) WEAK_FRAMEWORK_ARGS="$WEAK_FRAMEWORK_ARGS $2"; shift ;;
    --resources) RESOURCES="$2"; shift ;;
    --plist-extra) PLIST_EXTRA="$PLIST_EXTRA $2"; shift ;;
    --define) SWIFT_DEFINES="$SWIFT_DEFINES -D$2"; shift ;;
    *) SRC_ARGS="$SRC_ARGS $1" ;;
  esac
  shift
done
if [ "$DEBUG" -eq 1 ] && [ "$UNSIGNED_EXPLICIT" -eq 0 ] && [ -z "${ISB_UNSIGNED+x}" ]; then
  UNSIGNED=0
fi
export ISB_SWIFT_DEFINES="$SWIFT_DEFINES"
ARCH="$ISB_ARCH"
SRCS="$SRC_ARGS"
[ -n "$SRCS" ] || { echo "missing at least one .swift"; exit 1; }

# Debug mode is deliberately opt-in. It does not change the user's source:
# it creates a working copy, adds the logging/overlay runtime, and opens the
# official stikdebug://enable-jit request with bundle-id + PID + universal.js.
DEBUG_ASSET="$SKILL/assets/DebugSupport.swift"
STIK_QUERY=""
if [ "$DEBUG" -eq 1 ]; then
  STIK_QUERY='<key>LSApplicationQueriesSchemes</key><array><string>stikdebug</string></array>'
  [ -f "$DEBUG_ASSET" ] || { echo "DebugSupport.swift missing"; exit 1; }
  SRCS="$SRCS $DEBUG_ASSET"
  echo "    (debug StikDebug: runtime + get-task-allow + DBG overlay)"
fi

# The default is a signed ad-hoc IPA. LiveContainer/SideStore wrappers pass
# --unsigned explicitly because they re-sign or inject the guest.
# The active module cache and its PCMs are generated against the configured
# sysroot; no personal-path fallback exists.
# its PCMs are generated against this stable prefix; no /home fallback exists.
ROOT="${ISB_SYSROOT:-/opt/isb/sysroot}"
SW="$ISB_SW"
SF="$SW/usr/bin/swift-frontend"
SDK="$ISB_SDK"
OUT="$ISB_FOUNDATION_BUILD"
VFS="$ISB_VFS"
[ -e "$SDK" ] || {
  echo "SDK missing: $SDK" >&2
  exit 2
}
WORK="${ISB_BUILD_WORK:-/tmp/build-$APP-$ISB_ARCH-$$}"
CACHE_ROOT="${ISB_BUILD_CACHE:-/var/tmp/isb-build-cache}"
CACHE_DIR="$CACHE_ROOT/$APP-$ISB_ARCH-$OPT_MODE"
mkdir -p "$CACHE_DIR"
BIG="$CACHE_DIR/objc-cache"
OUTPUT="${ISB_OUTPUT:-$ISB_WORKSPACE/$APP.ipa}"
# Count by glob instead of `find | grep`: in this shell, grep inside a
# pipe may not terminate (measured 2026-10-07), and that stalled the whole build.
have_cache=0
for f in "$OUT"/swift_*.swiftmodule; do
  [ -f "$f" ] && { have_cache=1; break; }
done
if [ ! -d "$OUT" ] || [ "$have_cache" -eq 0 ]; then
  echo "PROFILE $ISB_ARCH has no Swift cache: $OUT" >&2
  [ "$ISB_ARCH" = "arm64e" ] && echo "Run build-arm64e-modules.sh on Linux/VM and copy the arm64e cache." >&2
  exit 1
fi
rm -rf "$WORK" && mkdir -p "$WORK"

# SWIFT RULE: with MULTIPLE files, top-level code (UIApplicationMain) is only
# allowed in a file literally named `main.swift`. We copy the sources
# to the work dir and rename the entry file to main.swift.
SRCLIST=""
nfiles=$(echo $SRCS | wc -w)
if [ "$nfiles" -gt 1 ]; then
  mainsrc=""
  for f in $SRCS; do
    case "$(basename "$f")" in
      main.swift) [ -z "$mainsrc" ] && mainsrc="$f" ;;
      *Main.swift) [ -z "$mainsrc" ] && mainsrc="$f" ;;
    esac
  done
  [ -n "$mainsrc" ] || mainsrc=$(echo $SRCS | awk '{for(i=1;i<=NF;i++) if ($i !~ /DebugSupport\.swift$/) {print $i; exit}}')
  mkdir -p "$WORK/src"
  for f in $SRCS; do
    if [ "$f" = "$mainsrc" ]; then
      cat "$f" > "$WORK/src/main.swift"
    else
      cat "$f" > "$WORK/src/$(basename "$f")"
    fi
  done
  SRCLIST=$(ls "$WORK"/src/*.swift)
  # main.swift FIRST in the list: file order affects resolution of
  # Foundation ObjC types (FileManager/UUID/Locale disappear if the first
  # file that imports UIKit is not main — measured 2026-08-19).
  others=""
  for f in $SRCLIST; do
    case "$f" in
      */main.swift) ;;
      *) others="$others $f" ;;
    esac
  done
  SRCLIST="$WORK/src/main.swift$others"
  echo "    (entry point: $(basename "$mainsrc") -> main.swift)"
  # Ensures the debug runtime is initialized before the run loop.
  if [ "$DEBUG" -eq 1 ] && contains_file "$WORK/src/main.swift" 'UIApplicationMain('; then
    sed -i '/UIApplicationMain(/i ISBDebugRuntime.bootstrap()' "$WORK/src/main.swift"
  fi
else
  SRCLIST="$SRCS"
fi

# --- PRIMARY-FILE MODE --------------------------------------------------------
# Default when there are 2+ files. Delegates compilation to build-parallel.py
# (-primary-file, file-by-file) and linking to link-ipa.sh. This avoids the
# cross-file whole-module degradation (Foundation disappears from other files
# when some file uses CoreGraphics).
if [ -z "$MODE" ]; then
  if [ "$nfiles" -gt 1 ]; then MODE=primary; else MODE=whole; fi
fi

if [ "$MODE" = "primary" ]; then
  BP="$SKILL/scripts/build-parallel.py"
  LI="$SKILL/scripts/link-ipa.sh"
  [ -f "$BP" ] || { echo "build-parallel.py missing"; exit 1; }
  [ -f "$LI" ] || { echo "link-ipa.sh missing"; exit 1; }

  # build-parallel.py compiles a DIRECTORY. With only 1 file, create the dir.
  if [ "$nfiles" -le 1 ]; then
    mkdir -p "$WORK/src"
    cat $SRCS > "$WORK/src/main.swift"
  fi

  echo "==> compiling (primary-file mode)"
  mkdir -p "$WORK/obj"
  CACHE_ARGS=""
  if [ "${ISB_INCREMENTAL:-0}" = "1" ]; then
    CACHE_ARGS="--incremental"
  else
    rm -rf "$CACHE_DIR/obj"
  fi
  mkdir -p "$CACHE_DIR/obj"
  python3 "$BP" --module "$APP" --src "$WORK/src" --out "$CACHE_DIR/obj" --jobs 3 $CACHE_ARGS || {
    echo ""
    echo "BUILD ABORTED during file-by-file compilation."
    exit 1
  }

  # Objective-C bridges are compiled separately against the SDK 26.5.
  EXTRA_OBJS=""
  for f in $OBJC_ARGS; do
    [ -f "$f" ] || { echo "ObjC bridge missing: $f"; exit 1; }
    base=$(basename "$f" .m)
    mkdir -p "$WORK/extra-obj"
    LD="$ISB_GLIBC_ROOT/ld-linux-aarch64.so.1"
    [ -x "$LD" ] || { echo "glibc loader missing: $LD"; exit 1; }
    CLANG_LIB="$SW/usr/bin/clang-21"
    CLANG_RES="$SW/usr/lib/clang/21"
    BRIDGE_OK=0
    for attempt in 1 2 3; do
      rm -f "$WORK/extra-obj/$base.o" "$WORK/extra-obj/$base.o.tmp"
      if LD_LIBRARY_PATH="$ISB_GLIBC_ROOT" "$LD" --library-path "$ISB_GLIBC_ROOT" "$CLANG_LIB" -target "$ISB_TARGET" -isysroot "$SDK" -resource-dir "$CLANG_RES" -fmodules -fobjc-arc -c "$f" -o "$WORK/extra-obj/$base.o" \
        -F"$SDK/System/Library/Frameworks" -F"$SDK/System/Library/SubFrameworks" -I"$SDK/usr/include" \
        -fmodules-cache-path="$WORK/objc-cache" -Xclang -fmodule-feature -Xclang found_incompatible_headers__check_search_paths 2>"$WORK/extra-obj/$base.err" && [ -s "$WORK/extra-obj/$base.o" ]; then
        BRIDGE_OK=1; break
      fi
      echo "   (bridge Clang retry $attempt: $base)"
    done
    [ "$BRIDGE_OK" -eq 1 ] || { cat "$WORK/extra-obj/$base.err"; exit 1; }
    EXTRA_OBJS="$EXTRA_OBJS $WORK/extra-obj/$base.o"
  done

  LINK_ARGS=""
  [ "$DEBUG" -eq 1 ] && LINK_ARGS="--debug"
  [ -n "$EXTRA_OBJS" ] && LINK_ARGS="$LINK_ARGS --extra-obj-list $EXTRA_OBJS"
  [ -n "$FRAMEWORK_ARGS" ] && LINK_ARGS="$LINK_ARGS --extra-framework-list $FRAMEWORK_ARGS"
  [ -n "$WEAK_FRAMEWORK_ARGS" ] && LINK_ARGS="$LINK_ARGS --weak-framework-list $WEAK_FRAMEWORK_ARGS"
  [ -n "$PLIST_EXTRA" ] && LINK_ARGS="$LINK_ARGS --plist-extra $PLIST_EXTRA"
  [ -n "$RESOURCES" ] && LINK_ARGS="$LINK_ARGS --resources $RESOURCES"
  [ "$UNSIGNED" -eq 1 ] && LINK_ARGS="$LINK_ARGS --unsigned"
  sh "$LI" "$APP" "$BUNDLE" "$CACHE_DIR/obj" $LINK_ARGS
  exit 0
fi

echo "    (whole-module mode)"

# Extra frameworks are opt-in in this path too.
EXTRA_FRAMEWORK_FLAGS=""
for fw in $FRAMEWORK_ARGS; do
  EXTRA_FRAMEWORK_FLAGS="$EXTRA_FRAMEWORK_FLAGS -framework $fw"
  case "$fw" in
    NaturalLanguage) EXTRA_FRAMEWORK_FLAGS="$EXTRA_FRAMEWORK_FLAGS -lswiftNaturalLanguage" ;;
    CoreML) EXTRA_FRAMEWORK_FLAGS="$EXTRA_FRAMEWORK_FLAGS -lswiftCoreML" ;;
    Vision) EXTRA_FRAMEWORK_FLAGS="$EXTRA_FRAMEWORK_FLAGS -lswiftVision" ;;
    Accelerate) EXTRA_FRAMEWORK_FLAGS="$EXTRA_FRAMEWORK_FLAGS -lswiftAccelerate" ;;
    *) : ;;
  esac
done
WEAK_FRAMEWORK_FLAGS=""
for fw in $WEAK_FRAMEWORK_ARGS; do WEAK_FRAMEWORK_FLAGS="$WEAK_FRAMEWORK_FLAGS -weak_framework $fw"; done
FM_LINK=""
# Word comparison in pure shell: `echo | grep -w` may hang in this
# shell and the build would stand still with no visible child process (2026-10-07).
has_word(){ case " $1 " in *" $2 "*) return 0 ;; *) return 1 ;; esac; }
contains_file(){ while IFS= read -r _l; do case "$_l" in *"$2"*) return 0 ;; esac; done < "$1"; return 1; }
show_errors(){ _n=${2:-20}; while IFS= read -r _l; do case "$_l" in *error:*) printf '%s\n' "$_l"; _n=$((_n-1)); [ "$_n" -le 0 ] && return 0 ;; esac; done < "$1"; }
if has_word "$FRAMEWORK_ARGS" FoundationModels; then FM_LINK="-framework FoundationModels"; fi
if has_word "$WEAK_FRAMEWORK_ARGS" FoundationModels; then FM_LINK="-weak_framework FoundationModels"; fi

# --- builds the explicit module flags -----------------------------------------
MODS=""
for f in "$OUT"/swift_*.swiftmodule; do
  [ -f "$f" ] || continue
  n=$(basename "$f" .swiftmodule); n=${n#swift_}
  # XPC's Swift overlay creates an os<->XPC cycle; do not include this module.
  [ "$n" = "XPC" ] && continue
  # NOTE (2026-08-19): use TWO args (-swift-module-file X=path). The single-arg
  # format (-swift-module-file=X=path) makes modules load corrupted
  # with many files (Foundation/Dispatch types disappear).
  MODS="$MODS -swift-module-file=$n=$f"
done
for f in "$OUT"/clang_*.pcm; do
  [ -f "$f" ] || continue
  n=$(basename "$f" .pcm); n=${n#clang_}
  MODS="$MODS -Xcc -fmodule-file=$n=$f"
done

echo "==> compiling Swift (this may take a few minutes)"
n=0
until [ $n -ge 3 ]; do
  # iSH has a swift-frontend startup race (~15-25%): always retry
  if $SF -frontend -c -target "$ISB_TARGET" $ISB_CPU_ARGS -sdk "$SDK" \
      -enable-objc-interop -swift-version 5 $OPT_FLAGS \
      -disable-implicit-swift-modules -Xcc -fno-implicit-modules \
      -Xcc -fno-implicit-module-maps \
      -Xcc -ivfsoverlay -Xcc "$VFS" \
      -module-name "$APP" $SRCLIST \
      $MODS \
      -Xcc -fmodules-cache-path="$BIG" -Xcc -DCF_SWIFT_SENDABLE= \
      -o "$WORK/app.o" 2> "$WORK/swift.err"; then
    break
  fi
  if contains_file "$WORK/swift.err" 'error:'; then
    echo "COMPILATION ERROR:"; show_errors "$WORK/swift.err" 20; exit 1
  fi
  n=$((n + 1)); echo "   (startup race, attempt $n)"
done
[ -s "$WORK/app.o" ] || { echo "failed"; cat "$WORK/swift.err" | head -20; exit 1; }
echo "    object: $(stat -c %s "$WORK/app.o") bytes"

# MANDATORY GUARD: warnings that mean "the app opens and does not work".
# The classic case is a delegate signature that does not match the
# patched .swiftinterface: Swift only WARNS and the framework never calls the
# method -> live app with a BLACK SCREEN. See references/WARNINGS-FATAIS.md
CW="$SKILL/scripts/check-warnings.py"
if [ -f "$CW" ]; then
  python3 "$CW" "$WORK/swift.err" || {
    echo ""
    echo "BUILD ABORTED: the binary would compile, but the app would not work."
    exit 1
  }
fi

# Objective-C bridges also need to enter whole-module mode.
WHOLE_EXTRA_OBJS=""
for f in $OBJC_ARGS; do
  [ -f "$f" ] || { echo "ObjC bridge missing: $f"; exit 1; }
  base=$(basename "$f" .m)
  mkdir -p "$WORK/extra-obj"
  LD="$ISB_GLIBC_ROOT/ld-linux-aarch64.so.1"
  [ -x "$LD" ] || { echo "glibc loader missing: $LD"; exit 1; }
  CLANG_LIB="$SW/usr/bin/clang-21"
  CLANG_RES="$SW/usr/lib/clang/21"
  # The active toolchain root supplies the glibc loader and clang resources.
  LD_LIBRARY_PATH="$ISB_GLIBC_ROOT" "$LD" --library-path "$ISB_GLIBC_ROOT" "$CLANG_LIB" -target "$ISB_TARGET" -isysroot "$SDK" -resource-dir "$CLANG_RES" -fmodules -fobjc-arc -c "$f" -o "$WORK/extra-obj/$base.o" \
    -F"$SDK/System/Library/Frameworks" -F"$SDK/System/Library/SubFrameworks" -I"$SDK/usr/include" \
    -fmodules-cache-path="$WORK/objc-cache" -Xclang -fmodule-feature -Xclang found_incompatible_headers__check_search_paths 2>"$WORK/extra-obj/$base.err" || { cat "$WORK/extra-obj/$base.err"; exit 1; }
  WHOLE_EXTRA_OBJS="$WHOLE_EXTRA_OBJS $WORK/extra-obj/$base.o"
done

# UIKitCore generic stub is required for UIKit generic Swift classes.
EXTRAFW="${ISB_TOOLCHAIN_ROOT}/extrafw"
EXTRAFLAGS=""
if [ "${ISB_USE_UIKITCORE:-1}" = "1" ] && [ -f "$EXTRAFW/UIKitCore.framework/UIKitCore.tbd" ]; then
  EXTRAFLAGS="-F$EXTRAFW -framework UIKitCore"
fi
# arm64e/PAC uses the UIKitCore generic stub and client name.
CLIENT_ARGS="-client_name UIKit"
"$ISB_LINKER" -arch "$ARCH" -platform_version ios 26.5 26.5 \
  -syslibroot "$SDK" -L"$SDK/usr/lib" -L"$SDK/usr/lib/swift" \
  -lSystem -lobjc $CLIENT_ARGS $EXTRAFLAGS \
  -framework UIKit -framework Foundation $FM_LINK \
  -framework CoreGraphics \
  -framework QuartzCore -framework SwiftUI -framework CoreText -framework Combine \
  $EXTRA_FRAMEWORK_FLAGS $WEAK_FRAMEWORK_FLAGS -lswiftCore -lswiftFoundation -lswiftUIKit \
  -lswiftDarwin -lswiftObjectiveC -lswiftCoreGraphics -lswiftDispatch \
  -lswiftCoreFoundation -lswiftQuartzCore -rpath /usr/lib/swift -e _main \
  "$WORK/app.o" $WHOLE_EXTRA_OBJS -o "$WORK/$APP"

echo "==> packaging"
PAY="$WORK/Payload/$APP.app"
mkdir -p "$PAY"
cp "$WORK/$APP" "$PAY/$APP"
APP_VERSION="${ISB_APP_VERSION:-1.0}"
APP_BUILD="${ISB_APP_BUILD:-1}"
DISPLAY_NAME="${ISB_DISPLAY_NAME:-$APP}"

cat > "$PAY/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$APP</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE</string>
  <key>CFBundleName</key><string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
  <key>CFBundleVersion</key><string>$APP_BUILD</string>
  <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>MinimumOSVersion</key><string>26.5</string>
  <key>UIDeviceFamily</key><array><integer>1</integer></array>
  <key>UILaunchScreen</key><dict/>
  $PLIST_EXTRA
  $STIK_QUERY
</dict></plist>
EOF
# get-task-allow is required for StikDebug to attach to the process. Normal
# signing remains ad-hoc; the entitlement is preserved only in --debug.
if [ "$UNSIGNED" -eq 1 ]; then
  echo "    (unsigned: LiveContainer/SideStore will do the signing)"
elif [ "$DEBUG" -eq 1 ]; then
  cat > "$WORK/debug-entitlements.plist" <<EOT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>application-identifier</key><string>$BUNDLE</string>
  <key>get-task-allow</key><true/>
</dict></plist>
EOT
  ldid -S"$WORK/debug-entitlements.plist" "$PAY/$APP"
else
  ldid -S "$PAY/$APP"
fi
mkdir -p "$ISB_WORKSPACE"

# FINAL GUARD: invariants used by the LiveContainer patcher.
LCG="$SKILL/scripts/check-livecontainer.py"
if [ -f "$LCG" ]; then
  python3 "$LCG" "$PAY/$APP" || { echo "BUILD ABORTED: Mach-O incompatible with LiveContainer"; exit 1; }
fi

# FINAL GUARD: does the binary actually start?
# This does NOT depend on the compiler warning, which is inconsistent — it looks at what
# ended up in the binary. See references/WARNINGS-FATAIS.md
CE="$SKILL/scripts/check-entry.py"
if [ -f "$CE" ]; then
  python3 "$CE" "$PAY/$APP" || {
    echo ""
    echo "BUILD ABORTED: the IPA would be generated, but the app would not start."
    exit 1
  }
fi

(cd "$WORK" && zip -qr "$OUTPUT" Payload)
echo "==> ready: $OUTPUT"
ls -lh "$OUTPUT"
