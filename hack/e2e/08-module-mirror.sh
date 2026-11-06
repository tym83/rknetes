#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
ROOT=$(mktemp -d /work/tmp/module-mirror.XXXXXX)
mirror=
cleanup(){ if [[ -n "$mirror" ]]; then kill "$mirror" 2>/dev/null || true; wait "$mirror" 2>/dev/null || true; fi; }
trap cleanup EXIT
/work/out/optional/go-mirror --cache "$ROOT/cache" > "$ROOT/online.log" 2>&1 & mirror=$!
sleep 1
export GOPROXY=http://127.0.0.1:18085 GOMODCACHE="$ROOT/first" GOSUMDB=sum.golang.org
cd "$ROOT"
printf 'module rknetes.su/mirror-proof\n\ngo 1.26\n' > go.mod
go mod download -json rsc.io/quote@v1.5.2 > first.json
curl -fsS -D cache.headers http://127.0.0.1:18085/rsc.io/quote/@v/v1.5.2.zip -o cached.zip
grep 'X-Goshran-Cache: HIT' cache.headers
curl -fsS https://proxy.golang.org/rsc.io/quote/@v/v1.5.2.zip -o upstream.zip
cmp upstream.zip cached.zip
cleanup
/work/out/optional/go-mirror --cache "$ROOT/cache" --offline > "$ROOT/offline.log" 2>&1 & mirror=$!
sleep 1
export GOMODCACHE="$ROOT/second"
go mod download -json rsc.io/quote@v1.5.2 > second.json
python3 - <<'PY'
import json
first=json.load(open('first.json'));second=json.load(open('second.json'));assert first['Sum']==second['Sum'];assert first['GoModSum']==second['GoModSum'];print('PASS: two fresh Go caches, offline mirror and native SumDB verification',first['Sum'],first['GoModSum'])
PY
sha256sum cached.zip upstream.zip
cat "$ROOT/online.log"
echo 'PASS: dependency nationality changed only by the storage location; module bytes did not change'
