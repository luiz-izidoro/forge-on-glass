# Linux module-cache runner

The Dockerfile is an optional convenience wrapper. It does not ship Swift,
Apple SDK files, or generated modules. Mount those inputs explicitly:

```sh
docker build -t forge-on-glass-modules .
docker run --rm -it \
  -v "$PWD:/work/repo:ro" \
  -v "$USER_SWIFT:/opt/swift:ro" \
  -v "$USER_SDK:/opt/sdk:ro" \
  -v "$PWD/module-output:/out" \
  forge-on-glass-modules bash
```

Inside the container, the host must provide a Linux-compatible Swift 6.3.3
frontend and target SDK. Generate a target-specific graph first:

```sh
ISB_VM_SW=/opt/swift ISB_VM_SDK=/opt/sdk \
ISB_VM_VFS=/work/repo/vfs/overlay.yaml \
ISB_TARGET=arm64e-apple-ios26.5 \
/work/repo/scripts/scan-dependencies.sh /work/repo/seed.swift /out/fscan.json
```

Then run `orchestrator_vm633.py` with `ISB_VM_ROOT`, `ISB_VM_SW`, `ISB_VM_SDK`,
`ISB_VM_VFS`, `ISB_VM_OUT`, `ISB_VM_MODULE_CACHE`, and `FSCAN` all pointing to
mounted, stable paths. Copy only the resulting module cache to iSH; never
commit it. Run `scripts/check-module-cache.py` after transfer.

This image is not a substitute for the one-time glibc/Swift setup and does not
make the Apple SDK redistributable.
