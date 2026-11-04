#!/usr/bin/env bash
# Build optional experiments in the existing tenant builder, without replacing
# any binary in the validated native bundle or signed runtime package.
set -euo pipefail
cd /work/src/rknetes
[[ -f /work/kube/rknetes.conf ]] || exit 2
mkdir -p /work/out/optional /work/evidence/optional-build
GOMAXPROCS=4 go test -p 4 ./...
for name in presentation-office substitution-office telegram-office first-write watch-audience; do
  CGO_ENABLED=0 GOMAXPROCS=4 go build -p 4 -trimpath -o "/work/out/optional/$name" "./cmd/$name"
  go version -m "/work/out/optional/$name" > "/work/evidence/optional-build/$name.build-info.txt"
done
sha256sum /work/out/optional/* > /work/evidence/optional-build/binaries.sha256
find cmd pkg -name '*.go' -print0 | sort -z | xargs -0 sha256sum > /work/evidence/optional-build/source-files.sha256
sha256sum go.mod go.sum >> /work/evidence/optional-build/source-files.sha256
