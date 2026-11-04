#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../workshop/common.sh"
"$RK_ROOT/hack/dev/sync.sh"
builder sh -c 'cd /work/src/rknetes && GOMAXPROCS=4 go mod tidy && GOMAXPROCS=4 go test -p 4 ./... && CGO_ENABLED=0 GOMAXPROCS=4 go build -p 4 -trimpath -o /work/out/rknetes/ ./cmd/...'
builder cat /work/src/rknetes/go.sum > "$RK_ROOT/go.sum"
