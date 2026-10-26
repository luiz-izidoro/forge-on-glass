# Third-party notices

Forge on Glass is distributed under the MIT License (see [`LICENSE`](LICENSE)). It depends on
third-party software and platform components that remain under their own licenses and terms.

**No third-party source code, Apple SDK, toolchain binary, host application, IPA or generated
module is vendored in this repository.** Build inputs are supplied by the user; optional host and
debug applications are installed separately by the user. The tables below describe the projects
this repository documents or interoperates with, not a redistribution.

## Apple platform and SDK

| Component | Terms | Distribution |
| --- | --- | --- |
| iOS SDK, Xcode, Swift/UIKit/SwiftUI/Foundation, CoreML, Vision, Accelerate, NaturalLanguage, FoundationModels and related frameworks | Apple proprietary terms | Supplied by the user; not distributed here |
| Apple trademarks, product names and documentation | Apple terms | Descriptive use only |

The iOS SDK and Apple frameworks are **not** open source and are **not** licensed by this
repository. Users must obtain and use them under Apple's applicable terms.

## Build and runtime inputs

| Component | License | Distribution |
| --- | --- | --- |
| Swift toolchain (`swift-frontend`, runtime) | Apache-2.0 WITH Swift-exception | Supplied by the user |
| LLVM, clang, `ld64.lld`, `llvm-strip` | Apache-2.0 WITH LLVM-exception | Supplied by the user |
| glibc loader | LGPL-2.1-or-later | Supplied by the user |
| musl libc | MIT | Part of the host environment |
| Alpine Linux and packages (including BusyBox) | Individual package licenses (for example GPL-2.0-only) | Host environment; not distributed here |
| `ldid` | AGPL-3.0 | Supplied by the user |
| Python 3 | PSF-2.0 | Host environment |
| Info-ZIP `zip` | Info-ZIP license | Host environment |
| Docker / Ubuntu base image (optional module-cache runner) | Docker: Apache-2.0; Ubuntu packages: individual licenses | Built locally; not distributed here |

## Optional hosts and integrations

These projects are documented for interoperability. They are **not** bundled, linked into the
build output, or distributed by this repository.

| Project | License | Role |
| --- | --- | --- |
| [iSH](https://github.com/ish-app/ish) | GPL-3.0 (with additional terms) | Linux shell used for on-device builds |
| [LiveContainer](https://github.com/LiveContainer/LiveContainer) | AGPL-3.0 | Runs the unsigned/ad-hoc IPA on the same device |
| [SideStore](https://github.com/SideStore/SideStore) | AGPL-3.0 | Optional re-signing/install host |
| [StikDebug](https://github.com/StikDebug/StikDebug) | AGPL-3.0 | Optional on-device debug host |
| [OpenMinis](https://github.com/OpenMinis/OpenMinis) | GPL-3.0 | Harness that can consume this repository as a skill |

## Development and CI

| Component | Terms |
| --- | --- |
| GitHub Actions and hosted runners | GitHub terms; workflow actions keep their own licenses |
| `actions/checkout` | MIT |
| `github/codeql-action` | MIT |

Transitive dependencies and host packages keep their own licenses. Consult the upstream projects
and package metadata for the complete dependency graph.

## Trademarks and affiliation

Apple, Xcode, iOS, iPadOS, Swift, SwiftUI, UIKit, Foundation, CoreML, Vision, Accelerate,
NaturalLanguage, FoundationModels, iSH, Alpine, LiveContainer, SideStore, StikDebug, OpenMinis,
LLVM, clang, Python, Docker, Ubuntu and GitHub are trademarks or registered trademarks of their
respective owners.

The use of these names is descriptive and does not imply affiliation, endorsement, sponsorship or
partnership. This project is independent and is **not affiliated with, endorsed by, sponsored by,
or maintained by** Apple Inc., the iSH project, Alpine Linux, LiveContainer, SideStore, StikDebug,
OpenMinis, LLVM, the Python Software Foundation, Docker, Canonical or GitHub.

This notice is informational, not legal advice. Verify the current upstream license before
redistributing any third-party component.
