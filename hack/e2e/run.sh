#!/usr/bin/env bash
set -euo pipefail
cd /work/src/rknetes
export RK_BINARY_URL=${RK_BINARY_URL:-http://10.244.8.11:8080/rknetes}
RUN=${1:?unique evidence run name}
[[ "$RUN" =~ ^[a-z0-9-]+$ ]] || exit 2
shift
OUT=/work/evidence/$RUN
mkdir -p /work/evidence
mkdir "$OUT"
result=0
for test in "$@"; do
  [[ "$test" =~ ^[0-9][0-9]-[a-z0-9-]+$ ]] || exit 2
  code=0
  bash "hack/e2e/$test.sh" > "$OUT/$test.log" 2>&1 || code=$?
  printf '%s\n' "$code" > "$OUT/$test.exit-code"
  printf '%s: exit=%s\n' "$test" "$code"
  if [[ "$code" != 0 ]]; then tail -n 5 "$OUT/$test.log"; result=1; fi
done
exit "$result"
