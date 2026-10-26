# Normative best practices — forge-on-glass

> **Normative source.** This document consolidates the decisions that should guide
> new projects and new sessions. A historical document may explain how a
> discovery was made, but it cannot replace these rules. State consolidated
> on 2026-08-29.

## 1. Main rule: declare the evidence level

Never use “it works” without saying **where** it was verified. Use this classification:

| Level | Meaning | Can be announced as |
|---|---|---|
| S0 | not compiled or hypothesis only | planned/hypothesis |
| S1 | compiled | compiled |
| S2 | IPA passed Mach-O, SDK, symbol and signature validations | structurally valid |
| S3 | new IPA opened on the device/LiveContainer | runtime validated on that host/device |
| S4 | relevant functional flow was exercised on the device | functional in the tested scenario |

`check-module-cache.py` validates required module names, Swift/Clang file magic,
non-empty files, personal-path absence and arm64e/iOS 26.5 identity markers.
`neutral_refs` is reported for diagnosis; the cache must be generated against
the configured sysroot and architecture.

Structural validation proves S2 only when all applicable guards pass,
including `validate-ipa.sh`, `check-slice.py`, `check-entry.py`,
`check-undefined.py`, weak-linking and chained fixups. The signature is required
by default; an unsigned guest must declare `ISB_REQUIRE_SIGNATURE=0`. A
LiveContainer host transforms and re-signs the Mach-O, so validation before
import does not observe the file actually loaded afterwards.

When updating documentation, always record: date, commit, architecture, SDK,
iOS/device version, host (if any), command executed and result.

## 2. Architecture choice and build path

`arm64e.v1/PAC` is the only supported architecture and release profile. The
former arm64 compatibility path is discontinued and must not be restored or
used by consumers. LiveContainer, when used, receives an unsigned arm64e guest;
post-import host transformation is a separate compatibility experiment, not a
second builder profile.

### Default path for a new app

1. Use a **single Swift module**.
2. With two or more files, use `build-pure-ui.sh`, which uses `-primary-file` by
   default.
3. Start from the `assets/AppEntry.swift` template and confirm the real signature
   of the protocol in the patched SDK.
4. Use `PlatformVersionShim.swift` when `#available` is present.
5. Compile a minimal visible app before adding networking, persistence, AI or
   dependencies.
6. Run the guards and a runtime validation before calling it the production
   path.

Base command:

```sh
sh scripts/check-env.sh
sh scripts/build-pure-ui.sh MeuApp com.exemplo.meuapp main.swift Views.swift
sh scripts/validate-ipa.sh /var/minis/workspace/MeuApp.ipa
python3 scripts/check-debug-ipa.py /var/minis/workspace/MeuApp.ipa # --debug only
```

### Profiles

The canonical profile is native **arm64e.v1/PAC**, used for all builds and
release artifacts. A LiveContainer wrapper may produce an unsigned arm64e guest,
but the host's post-import transformation/re-signing is outside this builder's
S2 proof and requires separate device evidence.

- **Swift + ObjC hybrid:** mature plan B when a Swift API of the patched SDK
  degrades. Use Swift for the logic and ObjC/UIKit for the layer that actually
  needs the ObjC headers.
- **third-party project:** use `port-third-party.py`, but preserve the original
  project and record every adaptation. Do not turn a successful port into proof
  that all SPM projects are compatible.

### Never mix artifacts

Separate, at minimum, the arm64e cache, the temporary compilation directory,
output IPAs, logs and test bundle IDs.

Use `ISB_OUTPUT` for stable and unique names. Do not let concurrent builds
write `MeuApp.ipa`, and do not reuse objects from another architecture. PCMs and
`.swiftmodule` files carry the compiler/triple identity; mixing them can produce
an explicit error or, worse, a misleading diagnostic.

## 3. Swift and patched SDK rules

### Entry point and delegates

Before implementing any Apple protocol:

```sh
python3 scripts/check-protocol-sig.py UIApplicationDelegate didFinishLaunching
```

In the SDK used in this skill, the validated entry point is
`applicationDidFinishLaunching(_:)`. Do not replace it with
`application(_:didFinishLaunchingWithOptions:)` from memory: the exposed
signature may use `NSDictionary`, produce only a warning and prevent UIKit from
calling the method. Typical result: app alive with a black screen.

Never ignore:

- `nearly matches optional requirement`;
- protocol conformance warning;
- bridging warning in a delegate;
- absence of the corresponding ObjC thunk.

Builds must pass `check-warnings.py` and `check-entry.py`. The absence of a
warning does not exempt you from inspecting the binary, because the warning may
vary with the compilation context.

### Imports and helpers

On the pure path, keep the order that was validated:

```text
Foundation → SwiftUI → UIKit → CoreText → Dispatch → Combine
```

Include `assets/PureSwiftKit.swift` in small apps when it resolves the known
gaps. In large modules, prefer minimal local helpers if the kit introduces
type-checking or bridging degradations.

Practical rules:

- use `CGRect(origin:size:)`; `CGRectMake` may fail only at link time;
- for CoreGraphics APIs that lost their conveniences, use C functions or
  `UIBezierPath`;
- be explicit with types in closures, initializers and `UserDefaults`;
- avoid deep inference (`Self(...)` with an implicit member, `.success(x)` in
  generic contexts and ambiguous `Data?` conversions);
- keep the first compiled file with `Foundation` imported;
- use `-parse-as-library` for library modules, avoiding a duplicate `_main`.

### `-primary-file` is the default

The builder uses a single arm64e module and `-primary-file` by default. The
former separate-modules experiment is not part of this repository nor of the
production flow. Keep cross-file code in the single module and use `link-ipa.sh`
for the final link.

### Measured optimization

The recommended default is `ISB_OPT=O`. In the Swift 6.3.3 / iOS 26.5 SDK
toolchain, `-Osize` was measured as worse than `-O` on both axes: it compiled in
42 s versus 26 s and produced a 77,312 B executable versus 76,328 B. These are
local build and size measurements, not runtime performance (S2 structural; no
S4 inference).


Do not spend 10 minutes compiling a large app only to discover an entry point
error. Follow this sequence:

1. `sh scripts/check-env.sh` — toolchain, cache, space and profile.
2. `sh -n` on the scripts and `python3 -m py_compile` on the changed Python
   scripts.
3. `sh scripts/regression-suite.sh --quick` — especially after changing the
   linker, SDK, modules or flags.
4. a new build with a unique `ISB_OUTPUT`.
5. `check-warnings.py`, `check-entry.py`, `check-undefined.py` and
   `validate-ipa.sh`.
6. `sh scripts/acceptance-suite.sh` for the arm64e/PAC profile.
7. installation and visual test on the device.
8. only then add a dependency or a complex capability.

If the Swift process appears stalled, do not trust `/proc`: on iSH `cpu_ticks`
and `VmRSS` can stay at zero. Trust the output file and the return code. The
`swift-frontend` startup race requires retries; the scripts already perform
them. A process that is really stuck in the type-checker must be reduced to a
minimal case, not “cured” with an indefinite wait.

Keep at most three parallel jobs on iSH and preserve free space for temporary
objects. Never kill processes indiscriminately during a build; between
diagnostics, clean only known Swift workers and their workspaces.

## 5. Evidence-driven diagnosis

| Symptom | First hypothesis/test |
|---|---|
| process dies without output | retry; then classify OOM/race and read the full `.err` |
| app returns from main with code 0 | `check-entry.py`; `_main` does not call `UIApplicationMain` |
| app alive and black screen | warning/delegate/thunk; do not start with the logic |
| crash at launch | `check-undefined.py`, dependencies, crash log and slice |
| endless compilation | reduce to a minimal case and switch to `-primary-file` |
| failure only after importing into LiveContainer | investigate the host's transformation/re-signing |
| StikDebug session stopped at `Handling signal 1` | do not assume a crash; `universal.js` is not a generic logger |

For UI, use a synchronous visual trace on the screen itself. Give each probe a
different background color and record `viewDidLoad`, callbacks, files and
rendering. Only use attach/StikDebug after proving that the view and the event
exist.

## 6. Native AI and system frameworks

`NaturalLanguage`/`NLEmbedding` can be used through an ObjC bridge independent
of the Swift module, as long as the framework is declared and the binary is
audited. `FoundationModels` is capability-gated: linking the framework does not
guarantee that the model is available; on the device you must check
availability, Apple Intelligence and the model's preparation state.

For arm64e, all modules, PCMs, stdlib, SDK and linker must match the same triple
and compiler version. Do not mix arm64 cache with PAC code. Do not turn a symbol
validation into “validated real generation”: exercise
`LanguageModelSession.respond` on the device and record the result.

`BGAppRefreshTask` is an opportunity controlled by the system, not a daemon nor
a cron. In LiveContainer, the lifecycle and the registration may not represent
the normally installed application. Make the code tolerate a no-op and persist
each result incrementally.

## 7. Debug, signing and distribution

- `--debug` is opt-in and must be validated by `check-debug-ipa.py` on the final
  IPA;
- `get-task-allow` may be removed by the installer/re-signing;
- the LiveContainer guest and host have different bundle IDs; the StikDebug
  return uses the host ID;
- `ldid -S` is ad-hoc signing, not an Apple certificate;
- do not promise push, iCloud or other capabilities without compatible
  provisioning and signing;
- never commit the Apple SDK, binary modules, toolchain, credentials or
  generated IPAs. Use `.gitignore` and local artifact directories.

## 8. What to avoid — short list

- trying CPU subtype combinations without a post-import log;
- fixing a “black screen” by rewriting the logic before checking the delegate;
- using old documentation as the current state;
- compiling the entire app for every hypothesis;
- do not mix caches, objects or IPAs from different profiles;
- adding a framework “just in case” without declaring the reason and validating
  the link;
- using `UserDefaults` for a secret, token or API key;
- calling `BGTaskScheduler` as if execution were guaranteed;
- changing the production linker for an experimental backport without the
  acceptance suite and runtime;
- reporting “PASS” without recording exactly which S0–S4 level was obtained.

## 9. Closing checklist

Before delivering an IPA or declaring a stage complete:

- [ ] commit/tree and origin of the artifacts identified;
- [ ] profile, slice, SDK, minOS and bundle ID recorded;
- [ ] caches and workspaces isolated;
- [ ] warnings, entry point and undefined symbols verified;
- [ ] appropriate regression and acceptance suites executed;
- [ ] final IPA audited, not an old copy;
- [ ] runtime kept separate from static validation;
- [ ] limitations and host/device explicitly recorded;
- [ ] no secret or forbidden artifact in Git;
- [ ] next steps defined by evidence, not by trial and error.

Only `references/HANDOFF.md` and `references/WARNINGS-FATAIS.md` are current
operational guidance.


## 13. Maintenance of this documentation

When an investigation discovers a new rule:

1. reproduce it in a minimal case or automated test;
2. record the cause, symptom, fix and limit;
3. update `references/BEST-PRACTICES.md` first;
4. update the detailed technical document and mark old snapshots;
5. run the relevant suite and record the S0–S4 level;
6. only then commit with a message that describes the evidence.
7. keep a single current resumption point in `references/HANDOFF.md`; dated
   documents are history and remain under `references/`, never at the root.
8. record runtime facts with the artifact, host/device and version that
   produced them.

Do not accumulate “current state” in historical handoffs. A runtime fact must
always mention the artifact, host/device and version that produced it.
