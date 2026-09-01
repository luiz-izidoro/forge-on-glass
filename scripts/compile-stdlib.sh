#!/bin/sh
# compile-stdlib.sh — (re)build the iOS Swift stdlib binary modules from the SDK's
# text .swiftinterface files. Only needed if /opt/ios-toolchain/exp63/modules is
# gone AND the backup at /var/minis/shared/darwin-sdk/swift-modules-full is gone.
#
# WARNING: the core `Swift` module takes ~17 MINUTES on iSH (emulated). This is
# NOT a hang — iSH's /proc reports cpu=0 even while working. Wait it out.
# Total: ~20 min for all 4 modules. Run it and be patient.
set -e

SW=/opt/swift6.3
SF="$SW/usr/bin/swift-frontend"
SDK=/opt/ios-toolchain/iPhoneOS26.5.sdk
XRES="$SW/usr/lib/swift"
CACHE=/opt/ios-toolchain/exp63
MODS="$CACHE/modules"
mkdir -p "$MODS" "$CACHE"
MCACHE=/tmp/stdlib_mc; rm -rf "$MCACHE"; mkdir -p "$MCACHE"

# --- 1. SwiftShims.pcm (Clang module, seconds) ---
echo "[1] SwiftShims.pcm ..."
MM="$SDK/usr/lib/swift/shims/module.modulemap"
i=0; while [ $i -lt 6 ]; do
  timeout 90 env -i HOME=/root TERM=dumb "$SF" -emit-pcm -target arm64-apple-ios26.0 \
    -module-name SwiftShims "$MM" -o "$CACHE/SwiftShims.pcm" \
    -Xcc -isysroot -Xcc "$SDK" 2>/dev/null || true
  [ -s "$CACHE/SwiftShims.pcm" ] && break; i=$((i+1))
done
[ -s "$CACHE/SwiftShims.pcm" ] || { echo "SwiftShims.pcm failed"; exit 1; }
echo "    OK ($(wc -c <"$CACHE/SwiftShims.pcm")B)"

# --- 2. Get the exact per-module compile commands via scan-dependencies ---
echo "[2] scan-dependencies ..."
echo 'let a=[1]; import _Concurrency' > /tmp/seed.swift
i=0; while [ $i -lt 5 ]; do
  timeout 90 env -i HOME=/root TERM=dumb "$SF" -scan-dependencies \
    -target arm64-apple-ios26.0 -sdk "$SDK" -resource-dir "$XRES" \
    -module-cache-path "$MCACHE" /tmp/seed.swift -o /tmp/scan.json 2>/dev/null || true
  [ -s /tmp/scan.json ] && break; i=$((i+1))
done
[ -s /tmp/scan.json ] || { echo "scan failed"; exit 1; }

python3 - "$SF" "$CACHE" "$MODS" <<'PY'
import json, os, subprocess, sys, time
SF, CACHE, MODS = sys.argv[1], sys.argv[2], sys.argv[3]
ENV = {"HOME":"/root","TERM":"dumb","PATH":"/usr/bin:/bin"}
scan = json.load(open("/tmp/scan.json"))["modules"]
cmds = {}
for i in range(0, len(scan), 2):
    k = scan[i]
    if isinstance(k, dict) and "swift" in k:
        cl = scan[i+1]["details"]["swift"].get("commandLine")
        if cl: cmds[k["swift"]] = cl

def fix(cmd, name):
    out=[]; skip=False
    for a in cmd:
        if skip: skip=False; continue
        if a=="-o": skip=True; continue
        a=a.replace("aarch64-apple-ios26.5","arm64-apple-ios26.0").replace("arm64-apple-ios26.5","arm64-apple-ios26.0")
        if a.startswith("-swift-module-file=Swift="):
            a=f"-swift-module-file=Swift={CACHE}/Swift.swiftmodule.bak"
        if ("/tmp/" in a) and a.endswith(".swiftmodule") and "=" not in a:
            continue
        out.append(a)
    out += ["-Xcc", f"-fmodule-file=SwiftShims={CACHE}/SwiftShims.pcm"]
    return out

def build(name, wd):
    outdir=f"{MODS}/{name}.swiftmodule"; os.makedirs(outdir, exist_ok=True)
    out=f"{outdir}/arm64-apple-ios.swiftmodule"
    if os.path.exists(out) and os.path.getsize(out)>0:
        print(f"    {name}: exists"); return
    args=fix(cmds[name], name)
    full=[SF]+args+["-module-cache-path","/tmp/stdlib_mc","-o",out]
    print(f"    {name}: building (up to {wd//60} min, iSH /proc lies about cpu)...", flush=True)
    t0=time.time()
    p=subprocess.Popen(full, env=ENV, stderr=open(f"/tmp/mod_{name}.err","wb"), stdout=subprocess.DEVNULL)
    while p.poll() is None:
        if time.time()-t0>wd: p.kill(); print(f"    {name}: TIMEOUT"); return
        time.sleep(10)
    sz=os.path.getsize(out) if os.path.exists(out) else 0
    print(f"    {name}: rc={p.returncode} {int(time.time()-t0)}s {sz}B {'OK' if sz>0 else 'FAIL'}", flush=True)
    if sz>0 and name=="Swift":
        subprocess.run(["cp", out, f"{CACHE}/Swift.swiftmodule.bak"])

# order: Swift first (slow, ~17min), then the small ones
print("[3] Compiling stdlib modules (Swift core is ~17 min — DO NOT abort)...")
build("Swift", 1800)
# ensure the .bak exists for the others to reference
if not os.path.exists(f"{CACHE}/Swift.swiftmodule.bak"):
    src=f"{MODS}/Swift.swiftmodule/arm64-apple-ios.swiftmodule"
    if os.path.exists(src): subprocess.run(["cp", src, f"{CACHE}/Swift.swiftmodule.bak"])
for m in ("SwiftOnoneSupport","_StringProcessing","_Concurrency"):
    if m in cmds: build(m, 600)
PY

echo "[done] modules in $MODS:"
find "$MODS" -name '*.swiftmodule' -type f -exec sh -c 'echo "  $(basename $(dirname "$1")): $(wc -c <"$1")B"' _ {} \;
# refresh backup
BK=/var/minis/shared/darwin-sdk/swift-modules-full
mkdir -p "$BK"; cp -rL "$MODS" "$BK/" 2>/dev/null || true
cp "$CACHE/SwiftShims.pcm" "$BK/" 2>/dev/null || true
echo "Backup refreshed at $BK"
