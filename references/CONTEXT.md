# Context & Learnings — how this toolchain came to be

> **Nota de leitura:** as regras vigentes estão em
> [`BEST-PRACTICES.md`](BEST-PRACTICES.md). Este arquivo é contexto histórico:
> explica por que as decisões foram tomadas e não deve ser usado sozinho para
> classificar uma capacidade como validada.

This file gives a fresh session the *why* behind every decision, so it can
extend or repair the toolkit intelligently instead of re-discovering everything.

## The goal

Build native iOS `.ipa` apps with modern Swift, entirely inside iSH (Alpine
Linux, musl, aarch64 — an x86-emulated userland sandbox on iPhone), without a
Mac at build time.

## The environment (hard facts, learned the hard way)

- iSH runs an **x86 emulator**; native execution reports `aarch64` but syscalls
  are emulated and fragile.
- **`ptrace`, `chroot`, JIT are blocked** → no proot, qemu-user, gdb, strace,
  no alternate rootfs.
- **`/proc` is unreliable**: `cpu_ticks` and `VmRSS` read 0 even for a busy
  process. A 2000-line compile that SUCCEEDS shows cpu=0 the whole time. NEVER
  use CPU/RSS to detect a hang. Only the output file + rc are trustworthy.
- **Non-deterministic startup race**: ~15-25% of `swift-frontend` invocations
  die at startup with SIGTRAP (exit 133) or a silent exit (rc≠0, empty stderr,
  no output). Fix = retry. A *real* error always writes `error:` to stderr;
  an empty stderr + no output = the race → retry.
- **Subprocess spawning is unstable** → the `swiftc` *driver* (which forks
  swift-frontend) hangs. Only call `swift-frontend` directly.
- glibc binaries DO run if given a real glibc loader (we ship one under
  `/opt/xtool-glibc/lib`); musl `gcompat` is insufficient for Swift.

## Why Swift 6.3.2 specifically

Binary `.swiftmodule` files are locked to the EXACT compiler version. The open
iOS 26.5 SDK's stdlib interface says `interface-compiler-version 6.3.2`
(`swiftlang-6.3.2.1.x`). So the Linux toolchain MUST be swift.org **6.3.2**
(from download.swift.org, ubuntu24.04-aarch64), patchelf'd to our glibc loader.
6.2 gave version-mismatch errors. Apple's own binary modules are useless here
(their compiler tag ≠ swift.org's), which is also why no prebuilt Darwin Swift
SDK is publicly redistributable (Apple license) — confirmed via GitHub, Swift
Forums, HuggingFace searches.

## The core breakthrough

The Swift stdlib ships in the SDK only as **text `.swiftinterface`** (53,782
lines for `Swift`). swift-frontend must recompile it to a binary
`.swiftmodule` before any app compiles. On iSH this looked like a deadlock
(cpu=0 forever) — but it was just **slow**: it COMPLETED in ~17 minutes,
producing a 15 MB `Swift.swiftmodule`. Lesson: patience + trust only the output
file. Once the 4 stdlib modules are binary, an app compiles in **2 seconds**
(loading a binary module is cheap; compiling the interface is the 17-min cost,
done once and cached).

Method that worked (see scripts/compile-stdlib.sh):
1. `swift-frontend -scan-dependencies` (fast, ~6s) yields the EXACT per-module
   compile command (`modules[i].details.swift.commandLine`).
2. Build `SwiftShims.pcm` via `-emit-pcm` on the SDK shims modulemap.
3. Run each module's command in `-explicit-interface-module-build` mode, adding
   `-Xcc -fmodule-file=SwiftShims=<pcm>`, and NORMALIZING every target triple to
   `arm64-apple-ios26.0` (the scan command mixes 26.0 and 26.5, which conflict).
4. For non-core modules, repoint `-swift-module-file=Swift=…` to our prebuilt
   `Swift.swiftmodule`, and inject `_SwiftConcurrencyShims.pcm` too.

## The IPA pipeline (proven)

Swift source → `swift-frontend -c -target arm64-apple-ios26.0 -sdk <SDK>
-resource-dir <SW/usr/lib/swift> -I <modules> -Xcc -fmodule-file=SwiftShims=…`
→ Mach-O arm64 object (2s). Link with `clang -fuse-ld=lld -L <SDK>/usr/lib/swift
-framework UIKit …`. Sign with `ldid -S`. `zip` into `Payload/App.app`. Validated:
`platform ios / sdk 26.5 / minos 26.0`, links `libswiftCore.dylib`, carries a
swift-mangled symbol + `__swift5_typeref` section.

## Why the hybrid architecture (the key design choice)

`import UIKit`/`import Foundation`/`import SwiftUI` in Swift does NOT compile:
the nested Clang build of the Foundation module can't find SwiftShims, and the
`os_workgroup` Clang module (Dispatch→Foundation→UIKit dependency) fails with
`unexpected type name 'OS_object'`. We built 35 of 38 modules; that one ObjC-
runtime-visible module is the wall (details + fix ideas in LIMITATIONS.md).

Workaround that ships real apps TODAY: **hybrid**. Swift for all logic
(`@_cdecl` exports), Objective-C for the UIKit UI (compiles 100% via clang+SDK),
linked together. You lose SwiftUI/Swift-syntax UI, keep modern Swift everywhere
else.

## Toolchain inventory (paths)

- `/opt/swift6.3` — Swift 6.3.2 Linux toolchain (patchelf'd).
- `/opt/xtool-glibc/lib` — glibc loader + libs so the toolchain runs on musl.
- `/opt/ios-toolchain/iPhoneOS26.5.sdk` — open iOS 26.5 SDK.
- `/opt/ios-toolchain/exp63/modules` — the 4 prebuilt stdlib modules (the prize).
- `/opt/ios-toolchain/exp63/SwiftShims.pcm`.
- `/opt/ios-toolchain/foundation-build` — 35 explicit Foundation-chain modules
  (Combine, CoreFoundation, System, Observation, Darwin, ObjectiveC, …) +
  `_SwiftConcurrencyShims.pcm`. Use these to import those modules in pure Swift.
- `/var/minis/shared/darwin-sdk/swift-modules-full` — backup of the modules.
- `/var/minis/shared/darwin-sdk/PROCEDIMENTO-MAC.md` — how the SDK bundle was
  obtained from a Mac (one-time).
- Tools: `clang` (apk clang19), `ld64.lld` (apk lld), `ldid` (built from
  ProcursusTeam/ldid), `llvm-strip`, `zip`.

## 2026-08-18 — Dispatch/Foundation SOLVED via a real Linux (the big one)

A premissa da skill estava errada: o `DISPATCH_ASSUME_ABI_SINGLE_BEGIN` NÃO era
limitação da emulação x86 do iSH. O erro reproduziu num Linux real (VM) — a
causa raiz: o clang search path resolve `<dispatch/base.h>` para o base.h
LINUX do toolchain (`-isystem $SW/usr/lib/swift` precede o SDK), sem os macros
de bounds. Fix: symlinks `$SW/usr/lib/swift/{dispatch,os,CoreFoundation}` →
headers do SDK (VM e iSH). Com isso + 5 fixes (os_object explícito,
CoreFoundation do modulemap do SDK, `-DCF_SWIFT_SENDABLE=`, ObjectiveC antes
de CF, frameworks implícitos com SubFrameworks), a cadeia Foundation/Dispatch
foi construída na VM (swift.org 6.3.2) e passou a carregar no iSH —
`import Foundation` + `import Dispatch` em Swift puro funcionam (validado).
Receita: `references/DISPATCH-VIA-LINUX.md` + `references/linux-vm/RECEITA-DISPATCH-LINUX.md`.

## 2026-08-19 — Swift 6.3.3 + SwiftUICore compilado (UIKit no último passo)

**Swift 6.3.3 existe** (release de manutenção do branch 6.3) e foi adotado como
toolchain definitivo. O 6.3.3 NÃO corrige o bug dos tipos reexportados no
interface-compile — os patches continuam necessários — mas o build completo da
cadeia (orquestrador `orchestrator_vm633.py`, com sdk_mmaps/cf_extra/pre-pass3
ptrauth+CDispatch/UIUtilities) produziu **152 artefatos** em
`foundation-build633/` (91 pcm + 61 swift modules), incluindo
**SwiftUICore (4MB)** — o último muro (depois de Foundation/Dispatch) caiu.

O bug foi **bissectado em 8 mecanismos** (documentados em
`references/linux-vm/ESTADO-E-NEXT-STEPS.md` §2): tipos reexportados do clang
em contextos aninhados, members de extensões de outros módulos em corpos
`@inlinable`, `.init()` com `Self ==`, refs ao próprio módulo em cases de enum,
defaults com members clang, `@_originallyDefinedIn` sem availability, tipos
ausentes do SDK (o SDK 26.5 do bundle é inconsistente: Foundation sem
LineHeight/AdaptiveImageGlyph/CoreTextAttributes — vivem no CoreText como
extensions), e renames do clang que colidem com stubs (NSAdaptiveImageGlyph).

**UIKit**: todos os erros de tipo foram patchados (~30 patches no interface);
resta um **crash do compilador 6.3.3** no SILGen (`emitCBridgedToNativeValue` —
thunk de bridging de método @objc com tipo patchado não-bridgeable). O bissect
está documentado em `references/linux-vm/ESTADO-E-NEXT-STEPS.md` §3.

**On iSH, os módulos 6.3.3 carregam se**: `/opt/swift6.3.3` (já patchelf'd) +
symlink `${ISB_SYSROOT:-/opt/isb/sysroot}/swift-6.3.3` → `/opt/swift6.3.3` + os
symlinks de headers dispatch/os/CoreFoundation no toolchain + o CoreFoundation
modulemap em `Headers/Modules/`. O loader valida existência e TAMANHO dos
headers referenciados.
