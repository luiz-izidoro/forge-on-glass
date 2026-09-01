#!/usr/bin/env python3
"""sync-sdk-mtimes.py — alinha mtime/tamanho dos arquivos do SDK do iSH com os da VM.

POR QUE: os .pcm (Clang modules) gravam, para CADA header de entrada, o par
(tamanho, mtime). Ao carregar um .pcm construido na VM dentro do iSH, o Clang
compara e aborta com:
    error: file 'X' has been modified since the module file 'Y'
Como o CONTEUDO e' identico (mesmo SDK), basta replicar os mtimes.

Uso:
  # 1) na VM (gera o manifesto):
  python3 sync-sdk-mtimes.py dump <sdk-dir> > /tmp/mtimes.tsv
  # 2) no iSH (aplica):
  python3 sync-sdk-mtimes.py apply <sdk-dir> /tmp/mtimes.tsv
"""
import os, sys

EXTS = ('.h', '.modulemap', '.map', '.apinotes', '.swiftinterface', '.yaml')


def walk(root):
    for dirpath, _dirnames, filenames in os.walk(root):
        for fn in filenames:
            if fn.endswith(EXTS):
                yield os.path.join(dirpath, fn)


def cmd_dump(sdk):
    sdk = os.path.abspath(sdk)
    n = 0
    for p in walk(sdk):
        try:
            st = os.stat(p)
        except OSError:
            continue
        rel = os.path.relpath(p, sdk)
        sys.stdout.write(f'{rel}\t{int(st.st_mtime)}\t{st.st_size}\n')
        n += 1
    print(f'# {n} arquivos', file=sys.stderr)


def cmd_apply(sdk, manifest):
    sdk = os.path.abspath(sdk)
    ok = miss = diff = 0
    for line in open(manifest):
        if line.startswith('#') or not line.strip():
            continue
        rel, mtime, size = line.rstrip('\n').split('\t')
        p = os.path.join(sdk, rel)
        if not os.path.exists(p):
            miss += 1
            continue
        if os.path.getsize(p) != int(size):
            diff += 1
            continue
        os.utime(p, (int(mtime), int(mtime)))
        ok += 1
    print(f'mtimes aplicados: {ok} | ausentes: {miss} | tamanho divergente: {diff}')


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    if sys.argv[1] == 'dump':
        cmd_dump(sys.argv[2])
    elif sys.argv[1] == 'apply':
        cmd_apply(sys.argv[2], sys.argv[3])
    else:
        print(__doc__)
        sys.exit(1)
