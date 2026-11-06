#!/usr/bin/env bash
# Build identical release commands from two distinct source directories.
set -euo pipefail
export GOFLAGS=-mod=readonly GOMAXPROCS=4 CGO_ENABLED=0
SOURCE=/work/src/rknetes
SECOND=/work/repeat/rknetes-source
mkdir -p "$SECOND" /work/repeat/rknetes-bin /work/out/rknetes /work/evidence/repeat-build
cp -a "$SOURCE/cmd" "$SOURCE/pkg" "$SECOND/"
cp "$SOURCE/go.mod" "$SOURCE/go.sum" "$SECOND/"
cd "$SOURCE"
go test -p 4 ./...
for source in cmd/*/main.go; do
 name=${source%/main.go};name=${name##*/}
 go build -p 4 -trimpath -o "/work/out/rknetes/$name" "./cmd/$name"
 (cd "$SECOND" && go build -p 4 -trimpath -o "/work/repeat/rknetes-bin/$name" "./cmd/$name")
 cmp "/work/out/rknetes/$name" "/work/repeat/rknetes-bin/$name"
 go version -m "/work/out/rknetes/$name" > "/work/evidence/repeat-build/$name.buildinfo"
done
sha256sum /work/repeat/rknetes-bin/* > /work/evidence/repeat-build/repeat.sha256
find cmd pkg -name '*.go' -print0 | sort -z | xargs -0 sha256sum > /work/evidence/repeat-build/source.sha256
sha256sum go.mod go.sum >> /work/evidence/repeat-build/source.sha256
bash hack/dev/bpf.sh
sha256sum /work/out/rknetes/*.o > /work/evidence/repeat-build/bpf.sha256
printf 'PASS: all release commands match across separate source directories\n'
