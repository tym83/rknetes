#!/usr/bin/env bash
set -euo pipefail
[[ -d /work/src/rknetes ]] || exit 1
if ! command -v clang >/dev/null; then
  apt-get -qq update
  apt-get -qq install -y clang llvm libbpf-dev linux-libc-dev iproute2 >/dev/null
fi
mkdir -p /work/out/rknetes
clang -O2 -g -target bpf -D__TARGET_ARCH_x86 -I/usr/include/x86_64-linux-gnu \
  -c /work/src/rknetes/bpf/sovereign-16k.c -o /work/out/rknetes/sovereign-16k.o
