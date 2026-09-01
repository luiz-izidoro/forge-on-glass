# Publishing to GitHub — copyright & licensing analysis

> **Checklist atual:** antes de publicar ou criar um release, leia
> [`BEST-PRACTICES.md`](BEST-PRACTICES.md) e confirme que a árvore contém
> somente código/documentação permitidos. Esta análise trata propriedade
> intelectual; ela não substitui a auditoria técnica da IPA.

Question: can this skill (and the toolchain method) be published on GitHub
without copyright problems? Short answer: **the skill's own files — yes**;
**the on-device toolchain artifacts — NO, never commit those**. Details below.

> Not legal advice. This is an engineering risk assessment. When in doubt,
> ship only your original text/scripts and have users fetch Apple/Swift
> materials themselves.

## Safe to publish (your original work)

These are 100% written by us — MIT/Apache-2.0/your choice:

- `SKILL.md`, `references/*.md` — prose, method, learnings.
- `scripts/*.sh` — build/validate/env/vfs/compile scripts (original code).
- `assets/AppLogic.swift`, `assets/AppShell.m` — original sample app sources.

No Apple or Swift-project code is embedded in any of the above. The scripts
*reference* tools and *derive* files from the user's own local SDK at runtime;
they don't contain third-party code.

## MUST NOT publish (third-party IP)

Never commit these — they are Apple- or toolchain-copyrighted:

1. **The iOS SDK** (`iPhoneOS26.5.sdk`) — Apple headers, `.tbd` stubs,
   modulemaps, `.swiftinterface`. Apple SDK/Xcode license forbids redistribution.
2. **Any `.swiftmodule` / `.pcm` we compiled** — derivative works of Apple's
   `.swiftinterface` + headers. Same restriction.
3. **The `os.modulemap` patch as a full file** — it's Apple's modulemap with one
   line added = a derivative work. (That's why the skill ships a *script* that
   patches the user's local copy, not the file itself.)
4. **Any built `.ipa`** — its Mach-O links/embeds Swift runtime metadata and was
   built against Apple headers. Don't ship binaries.
5. **The Swift toolchain** (`/opt/swift6.3`) — Apache-2.0 with Runtime Library
   Exception, BUT redistributing the whole toolchain has its own terms; just
   link to download.swift.org instead.
6. **The Darwin `.artifactbundle`** from the Mac — contains Apple SDK material.
7. **glibc loader/libs** (`/opt/xtool-glibc`) — glibc is LGPL; extracted Ubuntu
   binaries have their own distribution terms. Point users to the source debs.

## The pattern that keeps you clean

Publish **instructions + scripts that fetch/derive** everything third-party on
the user's machine (which the user is licensed to use because they have Xcode /
a device). This is exactly how xtool, theos, and swift-sdk-darwin operate:

- Ship: your scripts, docs, sample sources, a LICENSE (MIT/Apache-2.0), and a
  clear README that says "you need Xcode 26 (Apple ID) and a device; the scripts
  use YOUR SDK."
- Fetch at runtime: Swift toolchain (download.swift.org), the SDK (the user's
  Xcode, or their own extraction), glibc (Ubuntu debs).
- Derive at runtime: patched modulemaps, compiled modules, the .ipa.

## Extra flags to set on the repo

- **LICENSE**: MIT or Apache-2.0 for your code. (Apache-2.0 pairs well with the
  Swift ecosystem.)
- **NOTICE / disclaimer**: state it's unofficial, not affiliated with Apple, and
  that users are responsible for complying with the Apple SDK/Xcode license and
  the Swift toolchain license.
- **No trademarks**: don't imply Apple endorsement; avoid "iOS"/"Xcode" in the
  repo *name* (fine in prose). "iSH", "Swift" — describe, don't brand.
- **ldid / tooling**: link to ProcursusTeam/ldid (its own license); don't vendor
  its source unless you preserve its license.
- **Signing**: the ad-hoc/self-sign flow is fine to document; don't ship anyone's
  certificates or provisioning profiles.

## Precedents (all public on GitHub, same model)

- `xtool-org/xtool` — builds iOS apps on Linux; ships code, not Apple SDK.
- `theos/theos` + `theos/sdks` — the SDKs repo hosts Apple headers and HAS drawn
  DMCA attention historically; do NOT mirror SDKs yourself.
- `kabiroberai/swift-sdk-darwin` — generates the bundle from the user's Xcode.

## Verdict

Publishing **this skill's original files** (scripts + docs + sample Swift/ObjC)
under MIT/Apache-2.0 is fine. Keep every Apple/Swift/glibc artifact OUT of the
repo and have the scripts obtain them from the user's own licensed sources. Add
a LICENSE + an "unofficial / not affiliated with Apple" disclaimer.
