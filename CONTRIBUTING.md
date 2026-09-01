# Contributing

This project publishes build recipes, original scripts, documentation, and
small sample sources — never third-party or generated SDK material.

## Mandatory artifact rule

Do not commit Apple SDK files, headers, `.swiftinterface`, `.tbd`,
`.swiftmodule`, `.pcm`, toolchains, generated `.o`/`.dylib`/`.ipa`, credentials,
private keys, or files larger than 1 MiB. Run:

```sh
sh scripts/check-repo-clean.sh
```

before every commit. The same guard runs in CI. Generated patchsets contain
verbatim SDK context and must be written outside the repository.

## Testing

Run shell/Python syntax checks, `sh scripts/regression-suite.sh --quick`, and a
fresh acceptance build when changing the builder. Do not describe an app as
runtime-functional without stating its S0–S4 evidence level; see
`references/BEST-PRACTICES.md`.

The complete iOS build is intentionally not run in GitHub Actions because the
Apple SDK and local aarch64/iSH environment are user-provided inputs.
