#!/usr/bin/env bash
set -euo pipefail
export PATH=/work/bin:$PATH
[[ -d /work/src/rknetes ]] || exit 2
ROOT=$(mktemp -d /work/tmp/toolchain-mirror.XXXXXX)
${RK_GO_MIRROR:-/work/out/rknetes/go-mirror} --cache "$ROOT/cache" > "$ROOT/mirror.log" 2>&1 & mirror=$!
trap 'kill "$mirror" 2>/dev/null || true; wait "$mirror" 2>/dev/null || true' EXIT
sleep 1
cd "$ROOT"
GOTOOLCHAIN=go1.26.0 GOPROXY=http://127.0.0.1:18085 GOMODCACHE="$ROOT/modules" GOSUMDB=sum.golang.org go version
compiler=$(find "$ROOT/modules/golang.org" -path '*/bin/go' -type f)
[[ -x "$compiler" ]]
"$compiler" version
mkdir -p /work/import-tools/go
cp -a "${compiler%/bin/go}/." /work/import-tools/go/
cat "$ROOT/mirror.log"
echo 'PASS: the actual Go1.26.0 compiler was downloaded through the domestic module mirror with native checksum verification'
