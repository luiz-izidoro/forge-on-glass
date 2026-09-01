# External VM validation — 2026-09-01

The external Linux bootstrap was executed through the previously configured SSH
key, without placing credentials or remote host details in this repository.

## Neutral arm64e module cache

The public `scan-dependencies.sh` was copied to the Linux host and tested with
user-mounted Swift 6.3.3, iOS SDK 26.5, and the neutral VFS overlay:

```text
scan OK: modules=91
```

The corrected `orchestrator_vm633.py` was run in a detached `tmux` session with:

```text
ISB_VM_ROOT=/opt/isb/sysroot
ISB_VM_SW=/opt/isb/sysroot/swift-6.3.3
ISB_VM_SDK=/opt/isb/sysroot/iPhoneOS26.5.sdk
ISB_VM_VFS=/opt/isb/sysroot/vfs/overlay.yaml
ISB_VM_OUT=/opt/isb/sysroot/foundation-build633-arm64e-final
ISB_TARGET=arm64e-apple-ios26.5
```

Result:

```text
>>> FINAL: 93/93 modules; fails: []
```

The cache contained 40 Swift modules and 60 Clang PCMs after transfer. The
public `check-module-cache.py` reported:

```text
files=100 nonempty=100 neutral_refs=61 personal_refs=0
```

The valid PCMs/Swiftmodules contain no `/home/` references. The cache itself is
not committed because it is generated from Apple SDK material.

## Local consumption

The cache was transferred to the local neutral sysroot and used without a
custom cache override. A fresh arm64e SwiftUI IPA passed:

- exact arm64e subtype `0x80000002`;
- `LC_MAIN` and chained fixups;
- Swift entry/delegate guard;
- SDK 26.5 validation;
- weak-linked FoundationModels path.

The full arm64e acceptance suite, including the FoundationModels generation
*diagnostic build*, NaturalLanguage, and embeddings, passed with five fresh
IPAs. This is **S2 structural evidence**, not proof of device runtime.

## Arm64 limitation

The VM's available patched SDK interfaces and dependency graphs are arm64e.
Attempting to derive an arm64 graph from that input was rejected by Swift's
architecture checks. The existing arm64 production cache remains separate and
was not overwritten. A truly neutral arm64 cache requires an arm64-compatible
SDK/interface graph and must be generated independently.

Therefore:

- arm64 + LiveContainer remains the production route, with prior S3 evidence;
- arm64e is locally reproducible and structurally validated at S2;
- no S3 arm64e or S4 FoundationModels claim is made here.
