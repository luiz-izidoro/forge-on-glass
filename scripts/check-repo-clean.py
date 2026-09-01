#!/usr/bin/env python3
"""Fail if tracked files contain generated or sensitive material."""
import ipaddress, re, subprocess, sys
from pathlib import Path
files=[Path(x) for x in subprocess.check_output(["git","ls-files","-z"]).decode().split("\0") if x]
errors=[]
for p in files:
    n=str(p)
    if any(n.endswith(x) for x in (".tbd",".swiftmodule",".pcm",".swiftinterface",".ipa",".dylib",".o",".a")) or n.endswith(".sdk") or ".sdk/" in n: errors.append("proibido: "+n)
    try: data=p.read_bytes()
    except OSError: continue
    if len(data)>1024*1024: errors.append("maior que 1 MiB: "+n)
    text=data.decode("utf-8","replace")
    for m in re.finditer(r"(?<![0-9])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9])",text):
        try:
            if int(m.group().split('.')[0])<10: continue
            a=ipaddress.ip_address(m.group())
            if not (a.is_private or a.is_loopback or a.is_reserved): errors.append("IP público: "+n)
        except ValueError: pass
    if re.search(r"/home/[A-Za-z0-9_.-]+(?:/|$)",text): errors.append("home pessoal: "+n)
    if re.search(r"-----BEGIN (?:RSA|OPENSSH|EC|DSA) PRIVATE KEY-----",text): errors.append("chave privada: "+n)
if errors:
    print("REPO CLEAN: FAIL\n"+"\n".join(sorted(set(errors)))); sys.exit(1)
print("REPO CLEAN: PASS (%d arquivos rastreados)"%len(files))
