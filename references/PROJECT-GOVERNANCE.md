# Project governance and release contract

This repository is both an AI-facing skill and a reusable on-device build
project. The canonical operational profile is native `arm64e.v1/PAC`:
Swift 6.3.3, user-provided iOS SDK 26.5 and the local PAC linker.

## Source of truth

Read in this order:

1. `SKILL.md` — compact instructions for the agent;
2. `references/BEST-PRACTICES.md` — normative build/evidence policy;
3. `references/HANDOFF.md` — current continuation state;
4. `references/PROJECT-GUIDE.md` — internal and external project workflows;
5. `references/PUBLISHING.md`, `NOTICE.md`, `CONTRIBUTING.md` and `SECURITY.md`.

Dated reports are archival evidence only. They may contain old paths, profiles
or hypotheses and must never override the current handoff.

## Evidence contract

- S0: hypothesis or plan;
- S1: source compiled;
- S2: fresh IPA passed structural guards;
- S3: fresh IPA opened on a real device/LiveContainer;
- S4: relevant flow passed on that device.

Every runtime claim records date, commit, profile/slice, SDK, device/iOS and
host. The current S3/S4 evidence is only for iPhone17,1 / iOS 26.6 / the tested
LiveContainer host.

## Privacy and copyright

Ship only original scripts, documentation and sample sources. Never commit
Apple SDK/header/modulemap material, `.swiftinterface`, `.tbd`, `.swiftmodule`,
`.pcm`, IPAs, objects, toolchains, glibc binaries, generated SDK patchsets,
credentials, certificates, provisioning profiles, private keys, personal paths,
public server addresses or user exports.

Users obtain and derive SDK, Swift, glibc and module-cache inputs under their own
licenses. Generated patches contain SDK context and stay outside Git. Sanitize
all logs before sharing them in issues.

## Git policy

Use one concern per commit and an imperative English subject. Before committing:

```sh
sh scripts/verify-release.sh
sh scripts/regression-suite.sh --quick
python3 scripts/check-repo-clean.py
```

After committing, require a clean release tree:

```sh
VERIFY_RELEASE_CLEAN=1 sh scripts/verify-release.sh
```

Do not rewrite history merely to remove local generated files. Preserve history
and make cleanup/removal explicit in new commits.

## Reproducibility

A new user must be able to clone the repository, run `bootstrap.sh --check`, get
actionable missing-input diagnostics, provide licensed inputs, build the
arm64e module cache once on real Linux/VM, validate it with
`check-module-cache.py`, and consume it from iSH through `ISB_SYSROOT`.
Normal builds must not require SSH, a fixed username, `/var/minis/skills` or a
personal fallback path.

## Cleanup policy

Safe cleanup targets are Python bytecode, stale `/tmp` build/link directories,
failed candidates, old generated IPAs and scan caches. Preserve the active
arm64e cache, neutral sysroot, PAC linker and Swift frontend until replacements
are validated. Record destructive cleanup and never delete user source trees.
