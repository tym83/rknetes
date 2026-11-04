#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-calls
k -n rknet-system rollout status daemonset/maxlet --timeout=120s
k -n rknet-system port-forward service/maxlet 19443:443 > /work/tmp/max-forward.log 2>&1 &
forward=$!
trap 'kill "$forward" 2>/dev/null || true' EXIT
for _ in $(seq 1 20); do if grep -q Forwarding /work/tmp/max-forward.log; then break; fi; sleep 1; done
export HODATAY_MAX_SERVER=https://127.0.0.1:19443 HODATAY_MAX_CA=/work/tls/maxlet/tls.crt HODATAY_KUBECTL=/work/bin/kubectl
kubectl max --context admin@workshop -n "$NS" exec client -- echo max-recorded-call
k -n rknet-system logs -l app=maxlet --tail=3
# The session recorder writes actual upgraded stream bytes, not just request metadata.
found=false
for pod in $(k -n rknet-system get pods -l app=maxlet -o name); do
  if k -n rknet-system exec "$pod" -- sh -c 'grep -l '"'"'"direction":"server"'"'"' /archive/call-*.jsonl' 2>/dev/null; then found=true; fi
done
[[ "$found" == true ]]
echo 'PASS: authenticated MAX call succeeded and archived stream bytes'
