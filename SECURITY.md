# Security policy

The repository accepts private security reports through the maintainer's
contact channel (open a private issue or contact the maintainer directly; do
not disclose sensitive details in a public issue). If no private channel is
available, ask the maintainer for one before posting details.

Reportable examples include a reproducible build-script vulnerability that
leaks credentials, bypasses an explicit safety guard, or executes untrusted
project content outside the documented scope. Include the commit, exact
command, sanitized logs, and affected profile.

The following are **not vulnerabilities**: ad-hoc signing not installing
without re-signing, missing Apple Intelligence on a device, unsupported
SDK/device combinations listed in `references/VERSION-MATRIX.md`, and failures
caused by absent user-provided SDK/toolchain artifacts. Never include
credentials, private keys, public server addresses, personal paths, tokens,
Apple SDK/toolchain files, or generated IPAs in a public issue.

Before opening an issue, remove personal paths, hostnames, tokens, and generated
SDK/toolchain artifacts from logs. The project deliberately requires explicit
`ISB_REMOTE_HOST` and `ISB_REMOTE_USER` values and never ships remote defaults.
