# Reproducibility from zero

This repository contains only original recipes and source templates. It does not
contain an Apple SDK, Swift binaries, PCMs, `.swiftmodule`, `.tbd`, or IPAs.
Those inputs must be obtained by the user under the applicable licenses.

## Fresh Alpine/iSH setup

```sh
git clone https://github.com/luiz-izidoro/forge-on-glass.git forge-on-glass
cd forge-on-glass
sh bootstrap.sh --check
```

A fresh clone must provide the SDK in `ISB_SYSROOT/iPhoneOS26.5.sdk`, the
matching `vfs/overlay.yaml`, the Swift frontend, glibc loader, PAC linker and
validated arm64e cache. The bootstrap script reports all of these inputs
explicitly; stages 4/5 invoke the external Linux/VM generator and do not
silently manufacture a cache or linker on iSH. The former arm64 profile is
 discontinued and is not part of reproduction.

explicit, user-supplied URLs/archives plus SHA-256 values:

```sh
ISB_SWIFT_URL=... ISB_SWIFT_SHA256=... sh scripts/bootstrap.sh --step 2
ISB_SDK_ARCHIVE=... ISB_SDK_SHA256=... sh scripts/bootstrap.sh --step 3
```

The glibc loader step is intentionally explicit because it is assembled from
Ubuntu aarch64 packages and is not redistributed. Follow the exact commands in
`references/BOOTSTRAP.md`, then run the canonical arm64e module generator on a
real Linux/VM host.

Pure UIKit/SwiftUI imports additionally require a module cache built once on a
real Linux VM or Docker host using the user's SDK. The existing orchestrator is
`references/linux-vm/orchestrator_vm633.py`; its output is copied locally to
`/opt/ios-toolchain/foundation-build633-arm64e` and must not be committed.

The first build is always native arm64e/PAC:
```sh
sh scripts/check-env.sh
sh scripts/build-pure-ui.sh Demo com.example.demo assets/PureSwiftDemo.swift
sh scripts/validate-ipa.sh /var/minis/workspace/Demo.ipa
```

For an unsigned LiveContainer handoff, use the same arm64e builder with
`--unsigned`. The host may transform/re-sign the guest; that post-import result
is not covered by local structural validation. LiveContainer is an independent
third-party project: <https://github.com/LiveContainer/LiveContainer> (no
affiliation or endorsement).

For reproducible custom locations:

```sh
ISB_SYSROOT=/opt/isb/sysroot ISB_WORKSPACE="$PWD/out" \
  sh scripts/build-pure-ui.sh Demo com.example.demo assets/PureSwiftDemo.swift
```

For debug/StikDebug, the builder signs by default so `get-task-allow` is
preserved. Pass `ISB_UNSIGNED=1` or `--unsigned` only for a guest that will be
re-signed by LiveContainer/SideStore.

`ISB_OPT=Osize` for size experiments, and `ISB_STRIP=1` for symbol stripping.
`ISB_INCREMENTAL=1` enables the opt-in content-addressed object cache. A source,
flag, SDK, VFS, module, or compiler change invalidates the cache.

## Optional native AI diagnostic

Build the FoundationModels diagnostic only when the arm64e cache exists:

```sh
ISB_ARCH=arm64e sh scripts/build-pure-ui.sh FoundationModelsRuntime \
  com.forge.runtime assets/FoundationModelsRuntimeMain.swift \
  --primary-file --weak-framework FoundationModels --unsigned
```

Install/import that fresh IPA in the target runtime, tap **Gerar resposta**, and
record device, iOS, slice, host, prompt, response, and latency in the result
report. Structural acceptance is S2; only a successful device flow is S4.

## Verification ladder

```sh
sh scripts/check-repo-clean.sh
sh scripts/regression-suite.sh --quick
sh scripts/acceptance-suite.sh
ISB_ARCH=arm64e sh scripts/acceptance-suite-arm64e.sh
sh scripts/benchmark-build.sh
```

Do not treat `check-env.sh` or IPA validation as device runtime proof. See
`references/BEST-PRACTICES.md` and `references/VERSION-MATRIX.md`.
