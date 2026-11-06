#!/usr/bin/env bash
# Replace the upstream dirty release binary with an exact clean source build.
set -euo pipefail
export GOFLAGS=-mod=readonly
SOURCE=/work/src/kine-rknetes
REV=35f4319798cf3543e49f86c775a1f8c5c23b1e80
if [[ ! -d "$SOURCE/.git" ]]; then git clone --depth 1 --branch v0.17.1 https://github.com/k3s-io/kine.git "$SOURCE"; fi
cd "$SOURCE"
[[ "$(git rev-parse HEAD)" == "$REV" ]]
[[ -z "$(git status --porcelain --untracked-files=no)" ]]
mkdir -p /work/out/rknetes /work/evidence/kine-source /work/repeat/kine
GOMAXPROCS=4 go test -p 4 ./pkg/drivers/sqlite ./pkg/server
flags="-s -w -linkmode external -extldflags -static -X github.com/k3s-io/kine/pkg/version.Version=v0.17.1 -X github.com/k3s-io/kine/pkg/version.GitCommit=$REV"
for out in /work/out/rknetes/kine /work/repeat/kine/kine; do
 CGO_ENABLED=1 CGO_CFLAGS=-DSQLITE_USE_ALLOCA=1 GOMAXPROCS=4 go build -p 4 -trimpath -buildvcs=true -tags nats -ldflags "$flags" -o "$out" .
done
cmp /work/out/rknetes/kine /work/repeat/kine/kine
/work/out/rknetes/kine --version
go version -m /work/out/rknetes/kine > /work/evidence/kine-source/buildinfo.txt
grep 'vcs.modified=false' /work/evidence/kine-source/buildinfo.txt
printf '%s\n' "$REV" > /work/evidence/kine-source/source-commit.txt
sha256sum /work/out/rknetes/kine /work/repeat/kine/kine > /work/evidence/kine-source/repeat.sha256
git diff --exit-code
cp LICENSE /work/evidence/kine-source/LICENSE
printf 'PASS: clean pinned kine source, SQLite/server tests and byte-identical repeat build\n'
