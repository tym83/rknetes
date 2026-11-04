#!/usr/bin/env bash
# Runtime test in the tenant builder; local upstream fixture has no network policy.
set -euo pipefail
export PATH=/work/out/rknetes:$PATH
work=$(mktemp -d /work/tmp/goshran.XXXXXX)
trap '[ -z "${pid:-}" ] || kill "$pid" 2>/dev/null || true; rm -rf "$work"' EXIT
printf 'entries:\n  fixture:\n  - urls: [https://foreign.example/chart.tgz]\n' > "$work/index.yaml"
goshran --listen=127.0.0.1:18088 --index="$work/index.yaml" > "$work/server.log" 2>&1 &
pid=$!
for _ in $(seq 1 30); do if curl -fsS http://127.0.0.1:18088/healthz; then break; fi; sleep 1; done
curl -fsS http://127.0.0.1:18088/index.yaml | cmp - "$work/index.yaml"
curl -sS -D "$work/headers" -o /dev/null http://127.0.0.1:18088/v2/library/postgres/blobs/sha256:123
grep -q '307 Temporary Redirect' "$work/headers"
grep -qi 'location: https://registry-1.docker.io/v2/library/postgres/blobs/sha256:123' "$work/headers"
echo 'PASS: Goshran emits an actual 307 to Docker Hub and preserves absolute chart URLs'
