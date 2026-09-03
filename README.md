# iOS Swift Builder

Reusable AI skill and build toolkit for producing native iOS `.ipa` files inside
iSH. The repository contains only original scripts, documentation and sample
sources.

> Unofficial; not affiliated with Apple. Apple SDK/Xcode, Swift, glibc and
> third-party licenses remain the responsibility of each user.

## Current validated profile

```text
Swift 6.3.3
SDK iOS 26.5
Target arm64e-apple-ios26.5
Profile arm64e.v1/PAC
```

`validate-ipa.sh` requires one app, `LC_MAIN`, chained fixups and (by default)
a code signature. Use `ISB_REQUIRE_SIGNATURE=0` only for an explicitly unsigned
guest handoff. `check-livecontainer.py` validates the fixup payload.

## Quick start

```sh
sh scripts/check-env.sh
sh scripts/build-pure-ui.sh MyApp com.example.myapp main.swift
sh scripts/validate-ipa.sh /var/minis/workspace/MyApp.ipa
```

Use a unique `ISB_OUTPUT` for custom outputs. Multiple Swift files are compiled
as one module with `-primary-file`; the entry file must be `main.swift` or end
in `Main.swift`.

## Supported workflows

```sh
# Foundation/Dispatch
sh scripts/build-pure-foundation.sh FoundationApp main.swift

# Swift + Objective-C/UIKit
sh scripts/build-ipa.sh App com.example.app assets/AppLogic.swift assets/AppShell.m

# The `--weak-framework` form is mandatory for capability-gated AI.
sh scripts/build-pure-ui.sh AIApp com.example.ai main.swift \
  assets/FoundationModelsProbe.swift --weak-framework FoundationModels

# NaturalLanguage/NLEmbedding bridge
sh scripts/build-pure-ui.sh EmbedApp com.example.embed main.swift \
  assets/NativeEmbeddings.swift --extra-objc assets/NativeNLBridge.m \
  --extra-framework NaturalLanguage

# third-party project, outside this checkout
python3 scripts/port-third-party.py /tmp/project MyApp com.example.myapp
```

The separate-module builder is deprecated because it breaks String/NSString
bridging in the app module. Use the project guide for internal and external
workflows: [`references/PROJECT-GUIDE.md`](references/PROJECT-GUIDE.md).

## From zero

1. Clone the repository.
2. Run `sh bootstrap.sh --check`.
3. Follow [`REPRODUCE-FROM-ZERO.md`](REPRODUCE-FROM-ZERO.md) and
   [`references/BOOTSTRAP.md`](references/BOOTSTRAP.md).
4. Supply the licensed SDK, Swift 6.3.3 toolchain and glibc inputs.
5. Build the arm64e module cache once on real Linux/VM with
   `references/linux-vm/orchestrator_vm633.py`.
6. Copy and validate the cache, then run `sh scripts/check-env.sh`.

No SDK, toolchain, module cache, patchset, IPA, signing material or credential
is distributed by this repository.

## Governance and verification

Read [`references/BEST-PRACTICES.md`](references/BEST-PRACTICES.md),
[`references/HANDOFF.md`](references/HANDOFF.md) and
[`references/PROJECT-GOVERNANCE.md`](references/PROJECT-GOVERNANCE.md).

```sh
sh scripts/verify-release.sh
sh scripts/regression-suite.sh --quick
sh scripts/check-newcomer.sh
sh scripts/acceptance-suite.sh
```

Evidence levels are S0 hypothesis, S1 compiled source, S2 structurally valid
fresh IPA, S3 opened on device and S4 successful functional flow. Never promote
S2 to S3/S4 from static inspection.

## Publication boundary

Only original scripts, docs and sample sources may be committed. Never commit
Apple SDK files, headers, modulemaps, `.tbd`, `.swiftinterface`, `.swiftmodule`,
`.pcm`, generated binaries, IPAs, toolchains, glibc files, SDK patchsets with
verbatim context, credentials, private keys, personal paths or public addresses.
See [`NOTICE.md`](NOTICE.md), [`PUBLISHING.md`](references/PUBLISHING.md),
[`CONTRIBUTING.md`](CONTRIBUTING.md) and [`SECURITY.md`](SECURITY.md).
