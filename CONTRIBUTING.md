# Contributing

This project publishes build recipes, original scripts, documentation, and
small sample sources — never third-party or generated SDK material.

## Language

Repository documentation, code comments, commit messages, issue/PR text and CLI output are
**English**. Product UI strings may be bilingual; a localized string is a product feature, not
documentation. Keep identifiers and commands unchanged when translating.

## Mandatory artifact rule

Do not commit Apple SDK files, headers, `.swiftinterface`, `.tbd`,
`.swiftmodule`, `.pcm`, toolchains, generated `.o`/`.dylib`/`.ipa`, credentials,
private keys, or files larger than 1 MiB. Run:

```sh
python3 scripts/check-repo-clean.py
```

before every commit. The same guard runs in CI. Generated patchsets contain
verbatim SDK context and must be written outside the repository.

## Code of conduct

By participating, you agree to follow [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). Use the pull
request template and keep security reports private through GitHub Security Advisories.

## Testing

Run shell/Python syntax checks, `sh scripts/regression-suite.sh --quick`, and a
fresh acceptance build when changing the builder. Do not describe an app as
runtime-functional without stating its S0–S4 evidence level; see
`references/BEST-PRACTICES.md`.

The complete iOS build is intentionally not run in GitHub Actions because the
Apple SDK and local aarch64/iSH environment are user-provided inputs.
