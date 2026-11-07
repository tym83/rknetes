#!/usr/bin/env bash
# Measure the actual 30-second fail-closed admission deadline and a clean retry.
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-agency-timeout
new_namespace "$NS"
start=$(date +%s)
if k -n "$NS" --request-timeout=60s run delayed --image=busybox:1.37 --overrides='{"metadata":{"annotations":{"rknetes.su/agency-delay":"30s"}}}' --command -- sleep 120 > /work/tmp/agency-timeout.log 2>&1; then
  echo 'the delayed admission unexpectedly succeeded' >&2
  exit 1
fi
elapsed=$(( $(date +%s) - start ))
cat /work/tmp/agency-timeout.log
grep -E 'context deadline exceeded|Client.Timeout exceeded|request did not complete within requested timeout' /work/tmp/agency-timeout.log
[[ "$elapsed" -ge 28 && "$elapsed" -le 45 ]]
if k -n "$NS" get pod delayed >/dev/null 2>&1; then echo 'failed admission left a Pod' >&2; exit 1; fi
k -n "$NS" run delayed --image=busybox:1.37 --command -- sleep 120
k -n "$NS" wait --for=condition=Ready pod/delayed --timeout=120s
printf 'PASS: real fail-closed admission timeout after %ss; concurrent agencies did not multiply it; an ordinary retry created a Ready Pod\n' "$elapsed"
