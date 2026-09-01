# syntax=docker/dockerfile:1
# Optional Linux-side module-cache runner. The user must mount a licensed SDK
# and matching Swift toolchain; this image never contains Apple artifacts.
FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 ca-certificates bash coreutils tar zstd && rm -rf /var/lib/apt/lists/*
WORKDIR /work
COPY references/linux-vm/orchestrator_vm633.py /work/orchestrator_vm633.py
COPY scripts/scan-dependencies.sh /work/scan-dependencies.sh
ENTRYPOINT ["/bin/bash"]
