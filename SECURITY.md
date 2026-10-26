# Security policy

## Supported versions

| Version | Supported |
| --- | --- |
| 0.2.x | Yes |
| < 0.2 | No |

## Reporting a vulnerability

Report vulnerabilities privately through **GitHub Security Advisories** (the repository's
**Security** tab, then **Report a vulnerability**). Do not open a public issue for a security
problem.

Include, when possible:

- affected commit and profile (`arm64e.v1/PAC`);
- impacted script or component;
- impact and preconditions;
- a minimal reproduction using sanitized logs;
- suggested remediation, if known.

Never include credentials, private keys, tokens, Apple SDK/toolchain files, generated IPAs,
personal paths or public server addresses.

## Scope

In scope: build, bootstrap, validation and release scripts in this repository, and their documented
default behavior.

Out of scope: ad-hoc signing not installing without re-signing, missing Apple Intelligence on a
device, unsupported SDK/device combinations listed in `references/VERSION-MATRIX.md`, and failures
caused by absent user-provided SDK/toolchain artifacts.

## Handling

Maintainers will acknowledge reports on a best-effort basis, validate the issue, prepare a fix and
coordinate disclosure through the advisory. No bounty or response-time SLA is offered.
