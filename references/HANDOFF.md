# Current handoff — ios-swift-builder

**Date:** 2026-09-02
**Baseline:** `cb456b5` — complete arm64e runtime validation
**Profile:** arm64e.v1/PAC · Swift 6.3.3 · iOS SDK 26.5
**Runtime host:** iPhone17,1 · iOS 26.6 · LiveContainer (exact version not recorded)

## Validated result

The canonical arm64e matrix passed structural validation and the user exercised
its flows on the device/host above. S3/S4 evidence:

- SwiftUI/UIKit UI rendered;
- Foundation/Dispatch file create/exists, group PASS, 11 ms;
- TortureTest/Diffable: 37/37;
- Swift+ObjC hybrid callback;
- debug/StikDebug overlay;
- CoreML/Vision/Accelerate vDSP `[5,7,9]`;
- NaturalLanguage model available;
- FoundationModels `respond(to:)`: response `OK`, 1995 ms;
- NLEmbedding bridge: availability true, dimension 640, vector count 640,
  phased diagnostic PASS.

This evidence is specific to this device, iOS and LiveContainer host. Other
hosts, devices, iOS/SDK versions, iSH on iPad and LiveContainer versions are
untested.

## Current source of truth

Read `BEST-PRACTICES.md`, this file, `PROJECT-GOVERNANCE.md` and
`PROJECT-GUIDE.md`. Dated reports and old handoffs under `references/` are
archival evidence only and must not override this file.

## Required checks

```sh
sh scripts/check-env.sh
python3 scripts/check-module-cache.py /opt/ios-toolchain/foundation-build633-arm64e
sh scripts/regression-suite.sh --quick
sh scripts/verify-docs.sh
sh scripts/check-newcomer.sh
sh scripts/acceptance-suite.sh
sh scripts/verify-release.sh
```

The acceptance suite creates fresh arm64e IPAs and checks exact slice/subtype,
PAC/chained fixups, entry point, undefined symbols, weak-link and IPA structure.
It must run serially and use a fresh `ISB_ACCEPTANCE_WORK`/`ISB_WORKSPACE`.

## Internal projects

Use one Swift module and `-primary-file`, begin with a visible UI, add one
capability at a time, use a unique `ISB_OUTPUT`, and record source/commit,
profile, SDK, bundle ID and S0–S4 evidence. Consult
`check-protocol-sig.py` instead of guessing delegate signatures.

## External projects

Clone the original outside this checkout. Use `port-third-party.py`, pin source
and dependency versions, preserve licenses/attribution, and record every
adaptation. The separate-module builder is deprecated and must not be used for
production. Never copy third-party or generated material into this repository.

## Reproduction

A new user runs `bootstrap.sh --check`, follows `REPRODUCE-FROM-ZERO.md` and
`BOOTSTRAP.md`, supplies licensed SDK/Swift/glibc inputs, builds the arm64e
module cache once on real Linux/VM with `orchestrator_vm633.py`, validates it,
and consumes it from iSH through `ISB_SYSROOT`. Normal builds are local and
offline; no SSH, fixed username or personal path is required.

## Privacy/copyright

The repository ships only original scripts, documentation and sample sources.
Never commit SDKs, headers, modulemaps, Swift modules, PCMs, patchsets with SDK
context, IPAs, objects, toolchains, signing material, credentials, private keys,
personal paths, public addresses or user exports. Run `verify-release.sh` before
committing. Publication still requires the user to provide a Git remote URL;
never invent one.

## Cleanup status — 2026-09-03

The repository and local generated residue were cleaned. See
`references/CLEANUP-2026-09-03.md` for the preservation/removal inventory.
A fresh complete acceptance rerun exceeded the one-hour budget at embeddings;
this is not claimed as a new PASS. Existing device evidence and targeted
validation remain documented above.
