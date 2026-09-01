#!/usr/bin/env python3
"""check-debug-ipa.py — valida o pacote produzido com --debug.

Confere as três propriedades que StikDebug/LiveContainer precisam:
get-task-allow, consulta ao esquema stikdebug e instrumentacao do builder.
Não tenta anexar ao processo: isso é responsabilidade do StikDebug no device.
"""
import plistlib, re, subprocess, sys, tempfile, zipfile
from pathlib import Path

if len(sys.argv) != 2:
    print("uso: check-debug-ipa.py <App.ipa>"); raise SystemExit(2)
ipa = Path(sys.argv[1])
td = Path(tempfile.mkdtemp(prefix="isb-debug-check-"))
try:
    with zipfile.ZipFile(ipa) as z: z.extractall(td)
    apps = list((td / "Payload").glob("*.app"))
    if not apps: raise RuntimeError("Payload/*.app ausente")
    app = apps[0]
    exe = app / app.name.removesuffix(".app")
    pl = plistlib.loads((app / "Info.plist").read_bytes())
    ent = subprocess.run(["ldid", "-e", str(exe)], capture_output=True, text=True).stdout
    data = exe.read_bytes()
    checks = [
        ("get-task-allow", bool(re.search(r"get-task-allow.*true", ent, re.I | re.S)), ent),
        ("LSApplicationQueriesSchemes/stikdebug", "stikdebug" in pl.get("LSApplicationQueriesSchemes", []), str(pl)),
        ("DebugSupport", b"ios-swift-builder" in data and (b"stikdebug" in data or b"debug overlay" in data), "binary strings"),
    ]
    ok = True
    for name, good, detail in checks:
        print(("[OK]   " if good else "[FAIL] ") + name)
        if not good and name == "get-task-allow": print(detail)
        ok &= good
    raise SystemExit(0 if ok else 1)
finally:
    import shutil; shutil.rmtree(td, ignore_errors=True)
