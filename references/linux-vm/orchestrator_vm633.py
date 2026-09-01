#!/usr/bin/env python3
# orchestrator_vm.py — v4 FINAL: explicit-module build of Foundation+UIKit chain.
# Breakthroughs baked in:
#  A) symlink $SW/usr/lib/swift/{dispatch,os,CoreFoundation} -> SDK (run_build.sh)
#  B) pre-build SwiftShims/_SwiftConcurrencyShims/_AvailabilityInternal pcm
#  C) os_object built EXPLICITLY in pass 3 (needs _DarwinFoundation* + ObjectiveC)
#  D) inject os_object + ALL existing pcm + -DCF_SWIFT_SENDABLE= into every build
#  E) CoreFoundation built from the SDK framework modulemap + iframework path;
#     any other module's Linux-CF-modulemap refs swapped to the SDK mm
#  F) missing framework clang modules built implicitly into OUT (no cache copy)
import json, os, subprocess, time, glob

VM_ROOT = os.environ.get("ISB_VM_ROOT", os.path.expanduser("~/swift-ios-build"))

SW = os.environ.get("ISB_VM_SW", os.path.join(VM_ROOT, "swift-6.3.3"))
SF = f"{SW}/usr/bin/swift-frontend"
SDK = os.environ.get("ISB_VM_SDK", os.path.join(VM_ROOT, "iPhoneOS26.5.sdk"))
OUT = os.environ.get("ISB_VM_OUT", os.path.join(VM_ROOT, "foundation-build633"))
TARGET = os.environ.get("ISB_TARGET", "arm64-apple-ios26.0")
PCM_ONLY = os.environ.get("ISB_PCM_ONLY", "0") == "1"
VFS = os.environ.get("ISB_VM_VFS", os.path.join(VM_ROOT, "vfs/overlay.yaml"))
IMPC = os.environ.get("ISB_VM_MODULE_CACHE", os.path.join(VM_ROOT, "module-cache"))
os.makedirs(OUT, exist_ok=True)
ENV = dict(os.environ, HOME=os.path.expanduser("~"), TERM="dumb")
LINUX_CF_MM = f"{SW}/usr/lib/swift/CoreFoundation/module.modulemap"
SDK_CF_MM = f"{SDK}/System/Library/Frameworks/CoreFoundation.framework/Modules/module.modulemap"

def outpath(t, n):
    ext = "pcm" if t == "clang" else "swiftmodule"
    return f"{OUT}/{t}_{n}.{ext}"

def have(t, n):
    p = outpath(t, n)
    return os.path.exists(p) and os.path.getsize(p) > 0

def emit_pcm(name, modulemap, out, extra=()):
    if have("clang", name):
        return True
    args = [SF, "-emit-pcm", "-target", TARGET,
            "-module-name", name, modulemap, "-o", out,
            "-Xcc", "-isysroot", "-Xcc", SDK,
            "-Xcc", "-ivfsoverlay", "-Xcc", VFS,
            "-Xcc", "-fno-implicit-modules"] + list(extra)
    p = subprocess.run(args, env=ENV, capture_output=True, text=True)
    if p.returncode == 0 and os.path.getsize(out) > 0:
        print(f"[pre:{name}] OK", flush=True)
        return True
    print(f"[pre:{name}] FAIL:", [l for l in p.stderr.split("\n") if "error:" in l][:2], flush=True)
    return False

# --- SCAN GRAPH ---
scan_path = os.environ.get("FSCAN", "/tmp/fscan.json")
scan = json.load(open(scan_path))["modules"]
index = {}
deps = {}
order = []
for i in range(0, len(scan), 2):
    k = scan[i]
    v = scan[i + 1]
    if not isinstance(k, dict):
        continue
    if 'swift' in k:
        name, typ = k['swift'], 'swift'
    elif 'clang' in k:
        name, typ = k['clang'], 'clang'
    else:
        continue
    index[(typ, name)] = v
    dd = []
    for d in v.get('directDependencies', []):
        if 'swift' in d:
            dd.append(('swift', d['swift']))
        elif 'clang' in d:
            dd.append(('clang', d['clang']))
    deps[(typ, name)] = dd
    order.append((typ, name))

def remap(p):
    b = os.path.basename(p)
    if b.endswith('.pcm'):
        return outpath('clang', b.split('-')[0])
    if b.endswith('.swiftmodule'):
        return outpath('swift', b.split('-')[0])
    return p

def fix(cmd, mm_swap=None, module_name=None, drop_implicit=False):
    out = []
    skip = False
    i = 0
    while i < len(cmd):
        a = cmd[i]
        if a == "-o":
            skip = True
            i += 1
            continue
        if skip:
            skip = False
            i += 1
            continue
        # Linux dispatch modulemap refs -> drop
        if a.startswith("-fmodule-map-file=") and "/dispatch/module.modulemap" in a:
            if out and out[-1] == "-Xcc":
                out.pop()
            i += 1
            continue
        # Linux CoreFoundation modulemap refs -> SDK framework mm
        if a.startswith("-fmodule-map-file=") and LINUX_CF_MM in a:
            a = f"-fmodule-map-file={SDK_CF_MM}"
        if drop_implicit and ((a == "-fno-implicit-modules") or (a == "-Xcc" and i + 1 < len(cmd) and cmd[i + 1] == "-fno-implicit-modules")):
            i += 2 if (a == "-Xcc") else 1
            continue
        if a == "-module-name" and module_name and i + 1 < len(cmd):
            out += ["-module-name", module_name]
            i += 2
            continue
        if a == "-direct-clang-cc1-module-build" and mm_swap and i + 1 < len(cmd):
            out += ["-direct-clang-cc1-module-build", mm_swap]
            i += 2
            continue
        a = (a.replace("aarch64-apple-ios26.5", TARGET)
               .replace("arm64e-apple-ios26.5", TARGET)
               .replace("arm64e-apple-ios26.5.0", TARGET)
               .replace("arm64-apple-ios26.5", TARGET)
               .replace("arm64-apple-ios26.0", TARGET))
        if a.startswith("-swift-module-file=") and "=" in a:
            pre, val = a.split("=", 1)
            if "=" in val:
                nm, pth = val.split("=", 1)
                a = f"{pre}={nm}={remap(pth)}"
            else:
                a = f"{pre}={remap(val)}"
        elif a.startswith("-fmodule-file="):
            body = a[len("-fmodule-file="):]
            if "=" in body:
                nm, pth = body.split("=", 1)
                a = f"-fmodule-file={nm}={remap(pth)}"
            else:
                a = f"-fmodule-file={remap(body)}"
        elif ("/tmp/" in a) and (a.endswith(".swiftmodule") or a.endswith(".pcm")) and "=" not in a:
            i += 1
            continue
        if a == "-Xcc" and i + 1 < len(cmd) and mm_swap and cmd[i + 1].endswith("module.modulemap") and not cmd[i + 1].startswith("-"):
            out += ["-Xcc", mm_swap]
            i += 2
            continue
        # positional modulemap input (direct-clang-cc1-module-build arg handled above;
        # also handle a bare LINUX_CF_MM token)
        if a == LINUX_CF_MM:
            out.append(SDK_CF_MM)
            i += 1
            continue
        out.append(a)
        i += 1
    return out

def all_pcm_flags():
    fl = []
    for f in sorted(os.listdir(OUT)):
        if f.startswith("clang_") and f.endswith(".pcm"):
            nm = f[len("clang_"):-len(".pcm")]
            fl += ["-Xcc", f"-fmodule-file={nm}={OUT}/{f}"]
    return fl

def all_swift_flags():
    fl = []
    for f in sorted(os.listdir(OUT)):
        if f.startswith("swift_") and f.endswith(".swiftmodule"):
            nm = f[len("swift_"):-len(".swiftmodule")]
            fl.append("-swift-module-file=%s=%s" % (nm, os.path.join(OUT, f)))
    return fl

def common_extra():
    return (all_swift_flags() + ["-Xcc", "-ivfsoverlay", "-Xcc", VFS,
             "-Xcc", "-DCF_SWIFT_SENDABLE=",
             "-Xcc", f"-fmodules-cache-path={IMPC}"] + all_pcm_flags())

def run_build(typ, name, args, wd=3600):
    out = outpath(typ, name)
    full = [SF] + args + ["-o", out]
    t0 = time.time()
    p = subprocess.Popen(full, env=ENV, stderr=open(f"{OUT}/{typ}_{name}.err", "wb"), stdout=subprocess.DEVNULL)
    while p.poll() is None:
        if time.time() - t0 > wd:
            p.kill()
            break
        time.sleep(5)
    sz = os.path.getsize(out) if os.path.exists(out) else 0
    if p.returncode == 0 and sz > 0:
        print(f"[{typ}:{name}] OK {sz}B {int(time.time()-t0)}s", flush=True)
        return True
    try:
        er = open(f"{OUT}/{typ}_{name}.err", "rb").read().decode('utf8', 'ignore')
    except FileNotFoundError:
        er = ""
    print(f"[{typ}:{name}] FAIL:", [l for l in er.split(chr(10)) if 'error:' in l][:2], flush=True)
    return False

def cf_extra():
    """Extra flags for CoreFoundation module builds (NSObject nullability fix)."""
    return (["-Xcc", "-internal-iframework", "-Xcc", f"{SDK}/System/Library/Frameworks",
             "-Xcc", f"-fmodule-map-file={SDK}/usr/include/ObjectiveC.modulemap",
             "-Xcc", f"-fmodule-map-file={SDK}/usr/include/os.modulemap"])

def sdk_mmaps():
    """SDK modulemaps so objc/* headers map to the ObjectiveC module (no textual
    NSObject -> nullability conflict in framework pcm builds)."""
    return ["-Xcc", f"-fmodule-map-file={SDK}/usr/include/ObjectiveC.modulemap",
            "-Xcc", f"-fmodule-map-file={SDK}/usr/include/Darwin.modulemap",
            "-Xcc", f"-fmodule-map-file={SDK}/usr/include/DarwinFoundation1.modulemap",
            "-Xcc", f"-fmodule-map-file={SDK}/usr/include/DarwinFoundation2.modulemap",
            "-Xcc", f"-fmodule-map-file={SDK}/usr/include/DarwinFoundation3.modulemap",
            "-Xcc", f"-fmodule-map-file={SDK}/usr/include/os.modulemap"]

def build(typ, name, wd=3600):
    if have(typ, name):
        return True
    if PCM_ONLY and typ == 'swift':
        # PCM-only is an honest recovery mode: Swift interfaces are not
        # regenerated, while the Clang graph is still rebuilt hermetically.
        return True
    cmd = index[(typ, name)]['details'][typ].get('commandLine')
    if not cmd:
        return True
    args = fix(cmd)
    if typ == 'clang' and name == 'CoreFoundation':
        args = fix(cmd, mm_swap=SDK_CF_MM, module_name="CoreFoundation")
        args += sdk_mmaps()
        args += cf_extra()
    elif typ == 'clang' and name in ('Dispatch', 'os_workgroup', 'os_object'):
        # Dispatch/os headers import objc/NSObject. Use one coherent SDK
        # ObjectiveC map for every member of this chain.
        args = fix(cmd, module_name=name)
        args += ["-Xcc", "-internal-iframework", "-Xcc", f"{SDK}/System/Library/Frameworks"]
        args += ["-Xcc", f"-fmodule-map-file={SDK}/usr/include/ObjectiveC.modulemap"]
        args += ["-Xcc", f"-fmodule-map-file={SDK}/usr/include/os.modulemap"]
    elif typ == 'swift':
        # SDK swiftinterfaces reference Security/CFNetwork/SystemConfiguration
        # types without importing them — make them available in scope.
        for m in ('Security', 'CFNetwork', 'SystemConfiguration', 'UIUtilities'):
            if have('clang', m):
                args += ["-import-module", m]
        # Accessibility/CoreText interfaces use CoreFoundation.CGPoint without
        # importing CoreFoundation — make it available in scope.
        for m in ('CoreFoundation', 'QuartzCore', 'CoreGraphics', 'CoreText', 'os', 'Dispatch'):
            if have('clang', m) and name in ('Accessibility', 'CoreText', 'SwiftUICore', 'UIKit', 'DataDetection', 'CoreTransferable', 'Symbols', 'QuartzCore', 'DeveloperToolsSupport', 'OSLog', 'UniformTypeIdentifiers'):
                args += ["-import-module", m]
        args += ["-Onone"]
        # let the clang importer resolve re-exported framework modules
        # (e.g. Foundation.NSString via the swift Foundation module)
        for fw in ('Foundation', 'CoreFoundation', 'UIKit', 'CoreGraphics', 'CoreText', 'CDispatch', 'ptrauth', 'Security',
                   'CFNetwork', 'SystemConfiguration'):
            mm = f"{SDK}/System/Library/Frameworks/{fw}.framework/Modules/module.modulemap"
            if os.path.exists(mm):
                args += ["-Xcc", f"-fmodule-map-file={mm}"]
    else:
        args = fix(cmd)
    args += common_extra()
    return run_build(typ, name, args, wd)

# --- PRE-STEP ---
SHIMS_MM = f"{SDK}/usr/lib/swift/shims/module.modulemap"
emit_pcm("SwiftShims", SHIMS_MM, outpath("clang", "SwiftShims"))
emit_pcm("_SwiftConcurrencyShims", SHIMS_MM, outpath("clang", "_SwiftConcurrencyShims"))
emit_pcm("_AvailabilityInternal", f"{SDK}/usr/include/DarwinFoundation1.modulemap", outpath("clang", "_AvailabilityInternal"))

# --- PASS 1: topological explicit build of scan modules ---
visited = set()
stack = []
def visit(n):
    if n in visited:
        return
    visited.add(n)
    for d in deps.get(n, []):
        if d in index:
            visit(d)
    stack.append(n)
for r in [(t, n) for (t, n) in order if n != 'fscan']:
    visit(r)
# scan-dependencies may list sibling Swift modules in arbitrary order. These
# modules have a strict stdlib bootstrap order even when the graph only says
# they all depend on Swift.
_priority = {'Swift': 0, 'SwiftOnoneSupport': 1, '_Concurrency': 2,
             '_StringProcessing': 3, '_Builtin_float': 4}
stack.sort(key=lambda x: _priority.get(x[1], 10))

fails = []
for typ, name in stack:
    if name == 'fscan':
        continue
    if typ == 'clang' and name == 'CoreFoundation':
        # ObjectiveC must exist first (objc/NSObject.h maps to it; textual
        # fallback causes the NSObject nullability conflict)
        if not have('clang', 'ObjectiveC'):
            build('clang', 'ObjectiveC')
    if not build(typ, name):
        fails.append((typ, name))
print(f"\n>>> PASS1: {sum(1 for t, n in stack if have(t, n))}/{len(stack)} modules; fails: {fails}", flush=True)

# --- PASS 2: os_object explicitly (needs _DarwinFoundation1 + ObjectiveC) ---
if not have('clang', 'os_object'):
    ow_cmd = index.get(('clang', 'os_workgroup'), {}).get('details', {}).get('clang', {}).get('commandLine')
    if ow_cmd:
        args = fix(ow_cmd, module_name="os_object")
        args += common_extra()
        run_build('clang', 'os_object', args, 600)
    else:
        print("[os_object] no template command", flush=True)

# --- PASS 3: framework clang modules missing from the graph ---
wanted = set()
for (typ, name) in order:
    if typ == 'swift':
        for d in deps.get((typ, name), []):
            if d[0] == 'clang' and not have('clang', d[1]):
                wanted.add(d[1])
for (typ, name) in fails:
    if typ == 'swift':
        for d in deps.get((typ, name), []):
            if d[0] == 'clang' and not have('clang', d[1]):
                wanted.add(d[1])
# frameworks whose clang modules the swift interfaces need but the scan omits
for fw in ('Foundation', 'Accessibility', 'UIKit', 'QuartzCore', 'CoreTransferable', 'CoreGraphics', 'CoreText', 'CoreFoundation',
           'NaturalLanguage', 'FoundationModels', 'CoreML', 'Vision', 'Accelerate',
           'Symbols', 'DataDetection', 'OSLog', 'UniformTypeIdentifiers', 'DeveloperToolsSupport',
           'Security', 'CFNetwork', 'SystemConfiguration', 'UIUtilities', 'ptrauth'):
    if not have('clang', fw):
        wanted.add(fw)

base_cmd = (index.get(('clang', 'CoreGraphics'), {}).get('details', {}).get('clang', {}).get('commandLine')
             or index.get(('clang', 'ObjectiveC'), {}).get('details', {}).get('clang', {}).get('commandLine')
             or index.get(('clang', 'Darwin'), {}).get('details', {}).get('clang', {}).get('commandLine'))

def build_ptrauth():
    mm = os.path.join(VM_ROOT, "swift-6.3.3/usr/lib/swift/clang/include/module.modulemap")
    args = fix(base_cmd, mm_swap=mm, module_name="ptrauth", drop_implicit=True)
    args += common_extra()
    cleaned = []
    i = 0
    while i < len(args):
        if args[i] == "-Xcc" and i + 1 < len(args) and "clang/include/module.modulemap" in args[i + 1]:
            i += 2
            continue
        cleaned.append(args[i])
        i += 1
    args = cleaned
    return run_build('clang', 'ptrauth', args, 600)

def clean_cdispatch_maps(args):
    """Remove the SDK Dispatch map when emitting the Linux CDispatch PCM."""
    out = []
    i = 0
    while i < len(args):
        if args[i] == "-Xcc" and i + 1 < len(args) and "dispatch.modulemap" in args[i + 1]:
            i += 2
            continue
        if "dispatch.modulemap" in args[i]:
            i += 1
            continue
        out.append(args[i])
        i += 1
    return out

def build_cdispatch():
    mm = os.path.join(VM_ROOT, "swift-6.3.3/usr/lib/swift/dispatch.linux.bak/module.modulemap")
    args = fix(base_cmd, mm_swap=mm, module_name="CDispatch", drop_implicit=True)
    args = clean_cdispatch_maps(args)
    args += common_extra()
    return run_build('clang', 'CDispatch', args, 600)

# pre-pass3: ptrauth + CDispatch FIRST (frameworks below depend on them and
# would otherwise build them implicitly into the cache with mismatched flags)
if not have('clang', 'ptrauth'):
    build_ptrauth()
if not have('clang', 'CDispatch'):
    build_cdispatch()

fw_fails = []
for name in sorted(wanted):
    if have('clang', name):
        continue
    if name == 'CDispatch':
        mm = os.path.join(VM_ROOT, "swift-6.3.3/usr/lib/swift/dispatch.linux.bak/module.modulemap")
        args = clean_cdispatch_maps(fix(base_cmd, mm_swap=mm, module_name=name, drop_implicit=True))
        args += common_extra()
        if not run_build('clang', name, args, 600):
            fw_fails.append(name)
        continue
    if name == 'ptrauth':
        mm = os.path.join(VM_ROOT, "swift-6.3.3/usr/lib/swift/clang/include/module.modulemap")
        args = fix(base_cmd, mm_swap=mm, module_name=name, drop_implicit=True)
        args += common_extra()
        # the toolchain's clang/include/module.modulemap ALSO defines ptrauth -> drop the whole -Xcc pair
        cleaned = []
        i = 0
        while i < len(args):
            if args[i] == "-Xcc" and i + 1 < len(args) and "clang/include/module.modulemap" in args[i + 1]:
                i += 2
                continue
            cleaned.append(args[i])
            i += 1
        args = cleaned
        if not run_build('clang', name, args, 600):
            fw_fails.append(name)
        continue
    mm = f"{SDK}/System/Library/Frameworks/{name}.framework/Modules/module.modulemap"
    if not os.path.exists(mm):
        mm = f"{SDK}/System/Library/SubFrameworks/{name}.framework/Modules/module.modulemap"
    if not os.path.exists(mm):
        mm = f"{SDK}/usr/include/{name}.modulemap"
    if not os.path.exists(mm):
        print(f"[fw:{name}] no modulemap found", flush=True)
        fw_fails.append(name)
        continue
    args = fix(base_cmd, mm_swap=mm, module_name=name, drop_implicit=True)
    args += common_extra()
    args += sdk_mmaps()
    if name == 'CoreFoundation':
        args += cf_extra()
    args += ["-Xcc", "-internal-iframework", "-Xcc", f"{SDK}/System/Library/Frameworks"]
    args += ["-Xcc", "-F", "-Xcc", f"{SDK}/System/Library/SubFrameworks"]
    if not run_build('clang', name, args, 1800):
        fw_fails.append(name)
print(f"\n>>> PASS3 framework fails: {fw_fails}", flush=True)

# --- PASS 4: retry failed scan modules ---
fails4 = []
for typ, name in stack:
    if name == 'fscan':
        continue
    if not have(typ, name):
        if not build(typ, name):
            fails4.append((typ, name))

# --- PASS 5: verify CoreFoundation.pcm is clean; if not, full deterministic
# rebuild (keep only the pre-step pcms + os_object so pass-1 CF builds clean) ---
def cf_dirty():
    try:
        r = subprocess.run(["strings", outpath("clang", "CoreFoundation")],
                           capture_output=True, text=True)
        return r.stdout.count("objc/NSObject.h") > 0
    except Exception:
        return True

def full_rebuild():
    keep = {'clang_SwiftShims.pcm', 'clang__SwiftConcurrencyShims.pcm',
            'clang__AvailabilityInternal.pcm', 'clang_os_object.pcm'}
    for f in os.listdir(OUT):
        if f not in keep:
            os.remove(os.path.join(OUT, f))
    # recompute the framework list from scratch (wanted was computed pre-wipe)
    fw_names = set()
    for (typ, name) in order:
        if typ == 'swift':
            for d in deps.get((typ, name), []):
                if d[0] == 'clang':
                    fw_names.add(d[1])
    for fw in ('Foundation', 'Accessibility', 'UIKit', 'QuartzCore', 'CoreTransferable', 'CoreGraphics', 'CoreText', 'CoreFoundation',
               'NaturalLanguage', 'FoundationModels', 'CoreML', 'Vision', 'Accelerate',
               'Symbols', 'DataDetection', 'OSLog', 'UniformTypeIdentifiers', 'DeveloperToolsSupport',
               'Security', 'CFNetwork', 'SystemConfiguration'):
        fw_names.add(fw)
    # pass 1: scan stack (CF needs ObjectiveC first → clean mapping)
    for typ, name in stack:
        if name == 'fscan':
            continue
        if typ == 'clang' and name == 'CoreFoundation' and not have('clang', 'ObjectiveC'):
            build('clang', 'ObjectiveC')
        build(typ, name)
    # pass 3: frameworks
    for name in sorted(fw_names):
        if have('clang', name):
            continue
        if name == 'CDispatch':
            mm = os.path.join(VM_ROOT, "swift-6.3.3/usr/lib/swift/dispatch.linux.bak/module.modulemap")
            args = clean_cdispatch_maps(fix(base_cmd, mm_swap=mm, module_name=name, drop_implicit=True))
            args += common_extra()
            run_build('clang', name, args, 600)
            continue
        if name == 'ptrauth':
            mm = os.path.join(VM_ROOT, "swift-6.3.3/usr/lib/swift/clang/include/module.modulemap")
            args = fix(base_cmd, mm_swap=mm, module_name=name, drop_implicit=True)
            args += common_extra()
            cleaned = []
            i = 0
            while i < len(args):
                if args[i] == "-Xcc" and i + 1 < len(args) and "clang/include/module.modulemap" in args[i + 1]:
                    i += 2
                    continue
                cleaned.append(args[i])
                i += 1
            args = cleaned
            run_build('clang', name, args, 600)
            continue
        mm = f"{SDK}/System/Library/Frameworks/{name}.framework/Modules/module.modulemap"
        if not os.path.exists(mm):
            mm = f"{SDK}/usr/include/{name}.modulemap"
        if not os.path.exists(mm):
            continue
        args = fix(base_cmd, mm_swap=mm, module_name=name, drop_implicit=True)
        args += common_extra()
        args += sdk_mmaps()
        if name == 'CoreFoundation':
            args += cf_extra()
        args += ["-Xcc", "-internal-iframework", "-Xcc", f"{SDK}/System/Library/Frameworks"]
        args += ["-Xcc", "-F", "-Xcc", f"{SDK}/System/Library/SubFrameworks"]
        run_build('clang', name, args, 1800)
    # retry stack
    for typ, name in stack:
        if name == 'fscan':
            continue
        if not have(typ, name):
            build(typ, name)

for attempt in range(3):
    if have('clang', 'CoreFoundation') and cf_dirty():
        print(f"[verify:CoreFoundation] dirty (attempt {attempt+1}) — full rebuild", flush=True)
        full_rebuild()
    else:
        break

done = sum(1 for t, n in stack if have(t, n))
fails4 = [(t, n) for t, n in stack if n != 'fscan' and not have(t, n)]
print(f"\n>>> FINAL: {done}/{len(stack)} modules; fails: {fails4}", flush=True)
