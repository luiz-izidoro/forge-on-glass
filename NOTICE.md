# NOTICE — license scope and third-party materials

## License scope

Forge on Glass is distributed under the MIT License (see [`LICENSE`](LICENSE)). The MIT grant
applies only to original scripts, documentation and sample sources authored for this project.

## No vendored third-party material

This repository does **not** include or license the Apple iOS SDK, Apple headers,
`.swiftinterface`, `.tbd`, `.swiftmodule`, `.pcm`, SDK patches, generated binaries, the Swift
toolchain, Apple frameworks, host applications or generated IPAs. Users obtain those materials and
applications under their own licenses and terms.

The patch generator creates local, user-owned build inputs. Generated patches contain verbatim SDK
context and must remain outside this repository.

## Interoperability

[LiveContainer](https://github.com/LiveContainer/LiveContainer) runs iOS apps without installing
them. [OpenMinis](https://github.com/OpenMinis/OpenMinis) is an on-device AI agent harness that can
consume this repository as a skill. Both are independent third-party projects.

This repository is not affiliated with, endorsed by, sponsored by, or maintained by LiveContainer or
OpenMinis. Their names, logos, code and trademarks belong to their respective owners, and their
licenses and security guidance apply to their own software.

This repository was tested and validated with OpenMinis as a harness skill; that statement describes
interoperability, not endorsement, partnership or support.

## Third-party notices

See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for Apple, Swift, LLVM, iSH, Alpine,
LiveContainer, SideStore, StikDebug, OpenMinis and related license and affiliation notices.

## Trademarks and affiliation

Apple, Xcode, iOS, iPadOS, Swift, SwiftUI, UIKit, Foundation, CoreML, Vision, Accelerate,
NaturalLanguage, FoundationModels, iSH, Alpine, LiveContainer, SideStore, StikDebug, OpenMinis,
LLVM, clang, Python, Docker, Ubuntu and GitHub are trademarks or registered trademarks of their
respective owners. Their use is descriptive and does not imply affiliation or endorsement.

This project is independent and is **not affiliated with, endorsed by, sponsored by, or maintained
by** Apple Inc., the iSH project, Alpine Linux, LiveContainer, SideStore, StikDebug, OpenMinis,
LLVM, the Python Software Foundation, Docker, Canonical or GitHub.

## Legal notice

This notice is informational, not legal advice. Verify upstream licenses and terms before
redistributing any third-party component.
