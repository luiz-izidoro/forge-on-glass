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

The executable bootstrap step is now:

```sh
# On a user-controlled Ubuntu arm64 mirror, collect the required .deb files
# and create a checksum manifest containing their filenames.
sha256sum "$ISB_GLIBC_PACKAGES"/*.deb > "$ISB_GLIBC_SHA256"
ISB_GLIBC_PACKAGES=/path/to/ubuntu-arm64-debs \
ISB_GLIBC_SHA256=/path/to/ubuntu-arm64-debs.sha256 \
sh scripts/bootstrap-glibc.sh
```

The package directory and manifest are intentionally supplied by the user.
The script verifies every package before extracting it, extracts `data.tar.*`
without installing foreign packages into Alpine, copies only the required
runtime libraries, and fails unless `ld-linux-aarch64.so.1`, `libc.so.6`,
`libstdc++.so.6`, and `libgcc_s.so.1` are present. To run it through the staged
bootstrap, use `sh bootstrap.sh --step 6` with `ISB_GLIBC_PACKAGES`,
`ISB_GLIBC_SHA256`, and optionally `ISB_GLIBC_ROOT` set.

The required runtime set comes from Ubuntu 24.04 arm64 packages such as
`libc6`, `libstdc++6`, `gcc-14-base`, `zlib1g`, `libncurses6`, `libtinfo6`,
`libuuid1`, and `libcom-err2`, depending on the Swift frontend's dynamic
loader diagnostics. Do not download or redistribute these packages from this
repository.

## 1a. Manual fallback / rationale

The loader and libraries are glibc artifacts and must remain outside Git. The
old manual extraction procedure remains valid when package metadata or a
vendor-specific mirror requires it, but `bootstrap-glibc.sh` is the preferred
reproducible path.

## 2. Swift 6.3.3 Linux toolchain — canonical arm64e profile

```sh
cd /tmp
wget https://download.swift.org/swift-6.3.3-release/ubuntu2404-aarch64/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE-ubuntu24.04-aarch64.tar.gz
tar xzf swift-6.3.3-RELEASE-ubuntu24.04-aarch64.tar.gz
mv swift-6.3.3-RELEASE-ubuntu24.04-aarch64 /opt/swift6.3.3
PFX=/opt/xtool-glibc/lib
LP="$PFX:/opt/swift6.3.3/usr/lib/swift/linux:/opt/swift6.3.3/usr/lib/swift/host/compiler:/opt/swift6.3.3/usr/lib/swift/host"
patchelf --set-interpreter "$PFX/ld-linux-aarch64.so.1" /opt/swift6.3.3/usr/bin/swift-frontend
patchelf --set-rpath "$LP" /opt/swift6.3.3/usr/bin/swift-frontend
env -i HOME=/root TERM=dumb /opt/swift6.3.3/usr/bin/swift-frontend --version
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
The historical Mac artifactbundle notes refer to an older Swift 6.3.2
experiment; they are archival only. The current profile is Swift 6.3.3/arm64e.

## 4. Build the arm64e module cache on real Linux/VM

Pure Swift framework imports require a cache produced once on real Linux/VM
with the user's Swift 6.3.3 and iOS SDK 26.5:

```sh
FSCAN=/tmp/fscan.json python3 references/linux-vm/orchestrator_vm633.py
python3 scripts/check-module-cache.py /opt/ios-toolchain/foundation-build633-arm64e
```

Transfer only the validated generated cache to iSH. The cache, SDK, patchsets and
all toolchain artifacts stay outside Git. Run `check-env.sh` before building.
