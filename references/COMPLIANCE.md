# Compliance and repository hygiene

**Status:** reviewed 2026-10-26
**Scope:** repository content, documentation, history, workflows, third-party notices and
publication policy.

## Licensing

- Original scripts, documentation and sample sources are MIT licensed (see [`LICENSE`](../LICENSE)).
- License scope and third-party attribution are in [`NOTICE.md`](../NOTICE.md) and
  [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md).
- Apple SDKs, frameworks, toolchains, host applications, IPAs and generated modules are not
  vendored. Users supply them under their own licenses.
- Apple, iSH, Alpine, LiveContainer, SideStore, StikDebug, OpenMinis, LLVM, Python, Docker,
  Canonical and GitHub are independent third parties; no affiliation or endorsement is claimed.

## Documentation and language

- Repository documentation, code comments, commit messages and CLI output are in English.
- Sample UI strings and device evidence are English; observed output literals are preserved as
  evidence and are not rewritten.
- The reference index and script index list every maintained document and script.

## Security and privacy

- No SDK, toolchain, IPA, generated module, credential, token, private key or personal path is
  tracked.
- Users must provide licensed inputs outside the repository.
- GitHub secret scanning and push protection are enabled.
- Security reports use GitHub Security Advisories, as described in [`SECURITY.md`](../SECURITY.md).

## Dependency and release policy

- Routine Dependabot version PRs are disabled with `open-pull-requests-limit: 0` to avoid
  notification noise.
- Dependabot alerts and security updates remain enabled.
- The repository publishes **code only**: no GitHub Releases and no version tags.
- There is no manual release archive; the code on `main` is the deliverable.

## CI and branch protection

- Static CI validates documentation, repository hygiene, shell/Python syntax and newcomer
  diagnostics.
- CodeQL analyzes Python.
- `main` requires a pull request, the `static` and `Analyze python` checks, and linear history.
- Force-push, branch deletion and direct pushes by administrators are blocked.

## Validation

```sh
sh scripts/verify-docs.sh
sh scripts/check-newcomer.sh
python3 scripts/check-repo-clean.py
sh scripts/verify-release.sh
```

The full IPA build is intentionally not run in CI because the Apple SDK and toolchain are
user-provided inputs.

## Intentional exceptions

- Observed device output literals are preserved as evidence.
- Optional hosts and debug tools are documented for interoperability, not bundled.
- Runtime IPAs and Apple/toolchain artifacts remain outside Git.
