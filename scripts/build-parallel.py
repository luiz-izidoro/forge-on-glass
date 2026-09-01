#!/usr/bin/env python3
"""build-parallel.py — compila um modulo Swift arquivo-a-arquivo com
`-primary-file` e um limite de jobs simultaneos, depois entrega os .o.

POR QUE ISSO EXISTE (medido no iSH em 2026-08-22):
  - whole-module (todos os arquivos num processo) TRAVA o type-checker em
    modulos com genericos pesados (TCA): processo vivo, 0% CPU, sem .o apos
    60+ min. O MESMO conjunto compila em ~2 min por arquivo com -primary-file.
  - paralelismo alto -> OOM ("module file ... not found: Cannot allocate
    memory"). Cada swift-frontend carrega ~90 pcm/swiftmodule. Limite seguro
    medido: 3 jobs.
  - erros de OOM sao FALSOS erros de compilacao: se a mensagem contiver
    "Cannot allocate memory" o arquivo e' reenfileirado, nao reportado.

Uso:
  python3 build-parallel.py --module NAME --src DIR --out OBJDIR
                            [--dep-module NAME=path] [--jobs 3]
                            [--parse-as-library] [--emit-module PATH]
                            [--timeout 1800] [--extra-src FILE]...
"""
import argparse, hashlib, os, subprocess, sys, time, glob

ROOT = os.environ.get("ISB_SYSROOT", "/opt/isb/sysroot")
if not os.path.exists(ROOT):
    candidates = glob.glob("/home/*/swift-ios-build")
    if candidates:
        ROOT = candidates[0]
# Profiles are selected with ISB_ARCH=arm64 (default) or ISB_ARCH=arm64e.
# Never mix the prebuilt module cache between slices.
ARCH = os.environ.get("ISB_ARCH", "arm64")
if ARCH not in ("arm64", "arm64e"):
    raise SystemExit("ISB_ARCH invalido: %s (use arm64 ou arm64e)" % ARCH)
TARGET = os.environ.get("ISB_TARGET", ARCH + ("-apple-ios26.5" if ARCH == "arm64e" else "-apple-ios26.0"))
CPU = os.environ.get("ISB_CPU", "apple-a12" if ARCH == "arm64e" else "apple-a7")
SW = os.environ.get("ISB_SW", "/opt/swift6.3.3")
SF = SW + "/usr/bin/swift-frontend"
SDK = os.environ.get("ISB_SDK", ROOT + "/iPhoneOS26.5.sdk")
FB = os.environ.get("ISB_FOUNDATION_BUILD", "/opt/ios-toolchain/foundation-build633" + ("-arm64e" if ARCH == "arm64e" else ""))
VFS = os.environ.get("ISB_VFS", ROOT + "/vfs/overlay.yaml")
BIG = os.environ.get("ISB_MODULE_CACHE", "/var/tmp/isb-cache") + "/app-" + ARCH

OOM_MARKERS = ("Cannot allocate memory", "out of memory", "Killed")

# "Erros fantasma": o swift-frontend carrega os modulos de forma corrompida em
# algumas execucoes (determinstico POR EXECUCAO, varia entre execucoes). O
# sintoma e' um tipo/membro que existe deixar de resolver — tipicamente do
# Dispatch (DispatchQueue vira Foundation.DispatchQueue sem os inits) ou de
# membros estaticos declarados noutro arquivo do MESMO modulo.
# Retry resolve; aplicar "fix" nesses erros so estraga o fonte.
GHOST_MARKERS = (
    "cannot infer contextual base in reference to member 'userInitiated'",
    "cannot infer contextual base in reference to member 'live'",
    "cannot infer contextual base in reference to member 'fireAndForget'",
    "extra argument 'qos' in call",
    "is not a member type of class 'Foundation.DispatchQueue'",
    "cannot infer key path type from context",
    # iSH startup/module-cache race: a valid prebuilt module can be invisible
    # to one worker. Retry only this exact transient diagnostic.
    "no such module 'FoundationModels'",
)


def module_flags():
    f = []
    for p in sorted(glob.glob(FB + "/swift_*.swiftmodule")):
        n = os.path.basename(p)[len("swift_"):-len(".swiftmodule")]
        if n == "XPC":      # overlay Swift do XPC cria ciclo os<->XPC
            continue
        f.append("-swift-module-file=%s=%s" % (n, p))
    for p in sorted(glob.glob(FB + "/clang_*.pcm")):
        n = os.path.basename(p)[len("clang_"):-len(".pcm")]
        f += ["-Xcc", "-fmodule-file=%s=%s" % (n, p)]
    return f


OPT_MODE = os.environ.get("ISB_OPT", "O")
OPT_FLAGS = {"none": "-Onone", "O": "-O", "Osize": "-Osize"}
if OPT_MODE not in OPT_FLAGS:
    raise SystemExit("ISB_OPT invalido: %s (use none, O ou Osize)" % OPT_MODE)

BASE = ["-frontend", "-target", TARGET, "-target-cpu", CPU, "-sdk", SDK,
        "-enable-objc-interop", "-swift-version", "5", OPT_FLAGS[OPT_MODE]]
if os.environ.get("ISB_SWIFT_DEFINES"):
    BASE += os.environ["ISB_SWIFT_DEFINES"].split()
BASE += ["-disable-implicit-swift-modules",
        "-Xcc", "-fno-implicit-modules", "-Xcc", "-fno-implicit-module-maps",
        "-Xcc", "-ivfsoverlay", "-Xcc", VFS,
        "-Xcc", "-fmodules-cache-path=" + BIG,
        "-Xcc", "-DCF_SWIFT_SENDABLE="]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--module", required=True)
    ap.add_argument("--src", required=True, help="diretorio com os .swift")
    ap.add_argument("--out", required=True, help="diretorio de saida dos .o")
    ap.add_argument("--dep-module", action="append", default=[],
                    help="NAME=path.swiftmodule (repetivel)")
    ap.add_argument("--extra-src", action="append", default=[])
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--parse-as-library", action="store_true")
    ap.add_argument("--emit-module", default=None,
                    help="path do .swiftmodule a emitir (passo extra, 1 processo)")
    ap.add_argument("--timeout", type=int, default=1800)
    ap.add_argument("--incremental", action="store_true",
                    help="reuse valid objects from --out using a content manifest")
    a = ap.parse_args()

    os.makedirs(a.out, exist_ok=True)
    os.makedirs(BIG, exist_ok=True)
    srcs = sorted(glob.glob(os.path.join(a.src, "*.swift"))) + a.extra_src
    if not srcs:
        print("nenhum .swift em", a.src); return 2

    # main.swift PRIMEIRO (ordem afeta resolucao de tipos ObjC do Foundation)
    mains = [s for s in srcs if os.path.basename(s) == "main.swift"]
    srcs = mains + [s for s in srcs if s not in mains]

    mods = module_flags()
    for dm in a.dep_module:
        mods.append("-swift-module-file=" + dm)

    # Incremental cache is opt-in. The manifest includes every source, flags,
    # compiler, SDK, VFS and module artifact; stale objects are never reused.
    manifest = os.path.join(a.out, ".isb-manifest")
    cache_key = hashlib.sha256()
    cache_key.update((OPT_MODE + "\0" + TARGET + "\0" + CPU + "\0" +
                      SF + "\0" + SDK + "\0" + VFS + "\0" +
                      a.module + "\0" + str(a.parse_as_library) + "\0").encode())
    for s in srcs:
        cache_key.update(os.path.basename(s).encode() + b"\0")
        cache_key.update(open(s, "rb").read())
    for m in mods:
        cache_key.update(m.encode() + b"\0")
        # Module paths are part of the ABI input; hash their bytes too when
        # they refer to a local artifact, so replacing a PCM invalidates it.
        candidate = m.split("=", 2)[-1]
        if os.path.isfile(candidate):
            with open(candidate, "rb") as f:
                while True:
                    chunk = f.read(1024 * 1024)
                    if not chunk:
                        break
                    cache_key.update(chunk)
    key = cache_key.hexdigest()
    cached = set()
    if a.incremental and os.path.exists(manifest):
        old_key = open(manifest).read().strip()
        if old_key == key:
            cached = {os.path.splitext(os.path.basename(s))[0] for s in srcs
                      if os.path.exists(os.path.join(a.out,
                                      os.path.splitext(os.path.basename(s))[0] + ".o"))}
            if cached:
                print("incremental: reutilizando %d objeto(s)" % len(cached), flush=True)
        else:
            for old in glob.glob(os.path.join(a.out, "*.o")) + glob.glob(os.path.join(a.out, "*.err")):
                os.unlink(old)

    def cmd_for(primary, objpath):
        c = [SF] + BASE + ["-c"]
        if a.parse_as_library:
            c.append("-parse-as-library")
        c += ["-module-name", a.module, "-primary-file", primary]
        c += [s for s in srcs if s != primary]
        c += mods + ["-o", objpath]
        return c

    pending = [s for s in srcs if os.path.splitext(os.path.basename(s))[0] not in cached]
    running = {}   # popen -> (src, obj, errpath, t0)
    attempts = {}
    failed = []
    done = []
    t_start = time.time()

    while pending or running:
        while pending and len(running) < a.jobs:
            s = pending.pop(0)
            b = os.path.splitext(os.path.basename(s))[0]
            obj = os.path.join(a.out, b + ".o")
            errp = os.path.join(a.out, b + ".err")
            ef = open(errp, "w")
            p = subprocess.Popen(cmd_for(s, obj), stdout=subprocess.DEVNULL, stderr=ef)
            running[p] = (s, obj, errp, time.time(), ef, b)
            print("  [start] %s" % b, flush=True)

        time.sleep(3)
        for p in list(running):
            s, obj, errp, t0, ef, b = running[p]
            rc = p.poll()
            if rc is None:
                if time.time() - t0 > a.timeout:
                    p.kill(); ef.close(); del running[p]
                    failed.append((b, "TIMEOUT %ds" % a.timeout))
                    print("  [TIMEOUT] %s" % b, flush=True)
                continue
            ef.close(); del running[p]
            err = open(errp, errors="replace").read()
            if rc == 0 and os.path.exists(obj):
                done.append(b)
                print("  [ok] %s (%.0fs, %d B)" % (b, time.time() - t0,
                                                   os.path.getsize(obj)), flush=True)
                continue
            n = attempts.get(b, 0) + 1
            attempts[b] = n
            oom = any(m in err for m in OOM_MARKERS) or rc < 0
            ghost = any(m in err for m in GHOST_MARKERS)
            if oom and n <= 4:
                print("  [oom/race] %s -> retry %d" % (b, n), flush=True)
                pending.append(s)
            elif ghost and n <= 6:
                # modulo carregado corrompido nesta execucao -> so retry
                print("  [fantasma] %s -> retry %d" % (b, n), flush=True)
                pending.append(s)
            elif "error:" in err:
                msgs = sorted({l.split("error: ", 1)[1][:110]
                               for l in err.split("\n") if " error: " in l})
                failed.append((b, "; ".join(msgs[:4])))
                print("  [ERRO] %s: %s" % (b, msgs[0] if msgs else "?"), flush=True)
            elif n <= 4:
                pending.append(s)
                print("  [rc=%s sem erro] %s -> retry %d" % (rc, b, n), flush=True)
            else:
                failed.append((b, "rc=%s sem diagnostico" % rc))

    print("\n== %d ok, %d falhas (%.0fs) ==" % (len(done), len(failed),
                                                time.time() - t_start))
    for b, m in failed:
        print("  FALHOU %s: %s" % (b, m))
    if failed:
        return 1

    if a.incremental:
        tmp_manifest = manifest + ".tmp"
        with open(tmp_manifest, "w") as f:
            f.write(key + "\n")
        os.replace(tmp_manifest, manifest)

    # GUARDA: warnings que produzem um app que compila e NAO funciona.
    # (assinatura de delegate divergente do .swiftinterface patchado ->
    #  o framework nunca chama o metodo -> TELA PRETA no device)
    cw = os.path.join(os.path.dirname(os.path.abspath(__file__)), "check-warnings.py")
    if os.path.exists(cw):
        r = subprocess.call([sys.executable, cw, "--dir", a.out])
        if r != 0:
            print("\nBUILD ABORTADO: warnings fatais (o app abriria com tela preta).")
            return 1

    if a.emit_module:
        print("== emitindo %s ==" % a.emit_module)
        c = [SF] + BASE + ["-emit-module", "-module-name", a.module]
        if a.parse_as_library:
            c.append("-parse-as-library")
        c += srcs + mods + ["-o", a.emit_module]
        r = subprocess.run(c, capture_output=True, text=True)
        if r.returncode != 0 or not os.path.exists(a.emit_module):
            print(r.stderr[-3000:]); return 1
        print("   %s (%d B)" % (a.emit_module, os.path.getsize(a.emit_module)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
