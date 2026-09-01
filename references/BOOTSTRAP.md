# Bootstrap — rebuild the whole toolchain from zero

> **Operação excepcional:** só use se o toolchain/cache em `/opt` estiver
> ausente ou comprovadamente inválido. Para um projeto normal, comece em
> [`BEST-PRACTICES.md`](BEST-PRACTICES.md), rode `check-env.sh` e não recompile
> módulos que já estão válidos. Registre versões, hashes e origem de cada
> artefato; nunca misture caches de compiladores/triplas.

Use this only if the toolchain under `/opt` is gone. Ordered, with the Mac step
that must happen once. Every download URL/version was verified working in the
original session (Aug 2026); bump versions consistently if they 404.

## 0. Install base tools (on-device, iSH)

```sh
apk add clang19 lld zip xz zstd binutils patchelf git python3 wget
# ldid is NOT in apk — build it:
git clone --depth 1 https://github.com/ProcursusTeam/ldid /tmp/ldid
apk add libplist-dev openssl-dev pkgconf
cd /tmp/ldid && clang++ -c -std=c++11 -O0 -pipe -I. -DLDID_VERSION='"v2.1.5"' ldid.cpp -o ldid.o \
  && clang++ -o /usr/local/bin/ldid ldid.o $(pkg-config --libs libcrypto libplist-2.0)
# NOTE: g++ / clang -O2 fail with "Interrupted system call" on the big file; clang -O0 works.
```

## 1. glibc loader so glibc binaries run on musl

The Swift toolchain is glibc. Provide a real aarch64 glibc loader + libs:

```sh
# from Ubuntu 24.04 arm64 debs — extract loader + libc/libm/libstdc++/libgcc_s/
#   libz/libncurses/libtinfo/libuuid/libcom_err. Put them in /opt/xtool-glibc/lib.
# (The original session assembled this from ports.ubuntu.com libc6 + gcc-14 +
#  util-linux + ncurses arm64 packages via `ar x`/zstd.)
```
Key libs needed by swift-frontend: `ld-linux-aarch64.so.1`, libc/libm/libpthread,
libstdc++.so.6, libgcc_s.so.1, libz.so.1, libncurses.so.6, libtinfo.so.6,
libuuid.so.1, libcom_err.so.2.

## 2. Swift 6.3.2 Linux toolchain (MUST match the SDK's Swift version)

```sh
cd /tmp
wget https://download.swift.org/swift-6.3.2-release/ubuntu2404-aarch64/swift-6.3.2-RELEASE/swift-6.3.2-RELEASE-ubuntu24.04-aarch64.tar.gz
tar xzf swift-6.3.2-RELEASE-ubuntu24.04-aarch64.tar.gz
mv swift-6.3.2-RELEASE-ubuntu24.04-aarch64 /opt/swift6.3
# patchelf the frontend to our glibc loader + rpath:
PFX=/opt/xtool-glibc/lib
LP="$PFX:/opt/swift6.3/usr/lib/swift/linux:/opt/swift6.3/usr/lib/swift/host/compiler:/opt/swift6.3/usr/lib/swift/host"
patchelf --set-interpreter "$PFX/ld-linux-aarch64.so.1" /opt/swift6.3/usr/bin/swift-frontend
patchelf --set-rpath "$LP" /opt/swift6.3/usr/bin/swift-frontend
env -i HOME=/root TERM=dumb /opt/swift6.3/usr/bin/swift-frontend --version  # expect 6.3.2 (retry if blank)
```

## 3. iOS 26.5 SDK (open, headers + .tbd)

Sparse-clone ONE SDK folder (repo is huge):

```sh
cd /tmp && mkdir s && cd s
git clone --filter=blob:none --sparse --depth 1 https://github.com/xybp888/iOS-SDKs.git .
git sparse-checkout set iPhoneOS26.5.sdk
mv iPhoneOS26.5.sdk /opt/ios-toolchain/
```
iOS 26 note: UIKit split into SubFrameworks; ObjC builds need
`-F <SDK>/System/Library/SubFrameworks`.

### The Mac step (once) — only if you also want the *matched* Darwin toolset/SDK

The open SDK above is enough for the current pipeline. The original session also
generated a full `darwin.artifactbundle` on a Mac with Xcode 26 (Swift 6.3.2):

```sh
# ON A MAC with Xcode 26 (xcrun swift --version must be 6.3.x):
brew install rsync
git clone https://github.com/kabiroberai/swift-sdk-darwin && cd swift-sdk-darwin
./build.sh auto aarch64          # → output/darwin-linux-aarch64.artifactbundle.zip
# transfer the zip to /var/minis/shared/darwin-sdk/ on-device.
```
The bundle ships the SDK as text `.swiftinterface` only (prebuilt binary modules
are intentionally excluded and, being Apple-tagged, would be rejected by our
swift.org frontend anyway). It's useful mainly to get a version-matched SDK and
the Linux LLVM toolset (`ld64.lld`). See PROCEDIMENTO-MAC.md in that folder.

## 4. Build the iOS stdlib binary modules (~20 min, once)

```sh
sh /var/minis/skills/ios-swift-builder/scripts/compile-stdlib.sh
```
Produces `/opt/ios-toolchain/exp63/{modules/*.swiftmodule, SwiftShims.pcm}` and
refreshes the backup. REMEMBER: iSH `/proc` shows cpu=0 while it works — the
`Swift` module legitimately takes ~17 min. Do not abort.

## 5. (Optional) Foundation/Dispatch + UI framework chain for pure-Swift imports

**Since 2026-08-19 the full chain is prebuilt with Swift 6.3.3** (incl.
SwiftUICore) — no rebuild needed. If `/opt/ios-toolchain/foundation-build/`
(6.3.2) or the VM's `foundation-build633/` (6.3.3) is missing, rebuild on a
**real Linux box** (VM/Docker, any arch) with the matching swift.org toolchain
— complete recipes and orchestrators in `references/linux-vm/`
(`RECEITA-DISPATCH-LINUX.md` + `orchestrator_vm.py` for 6.3.2,
`orchestrator_vm633.py` for 6.3.3). Copy the resulting `foundation-build*/` to
iSH and install the companion symlinks (see `references/DISPATCH-VIA-LINUX.md`
and `references/linux-vm/ESTADO-E-NEXT-STEPS.md` §5 — the pcm validate
referenced paths and header sizes).

The old on-device partial build (35 modules, os_workgroup VFS fix) is
documented in CONTEXT.md; it is superseded by the VM builds.

## 6. Verify & build

```sh
sh /var/minis/skills/ios-swift-builder/scripts/check-env.sh
sh /var/minis/skills/ios-swift-builder/scripts/build-ipa.sh \
   SwiftApp com.example.swiftapp \
   /var/minis/skills/ios-swift-builder/assets/AppLogic.swift \
   /var/minis/skills/ios-swift-builder/assets/AppShell.m
sh /var/minis/skills/ios-swift-builder/scripts/validate-ipa.sh /var/minis/workspace/SwiftApp.ipa
```
