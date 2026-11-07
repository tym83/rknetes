#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-calls
k -n rknet-system rollout status daemonset/maxlet --timeout=120s
start_forward rknet-system service/maxlet 19443:443
trap stop_forward EXIT
export HODATAY_MAX_SERVER=https://127.0.0.1:19443 HODATAY_MAX_CA="$RK_TLS_DIR/maxlet/tls.crt" HODATAY_KUBECTL=/work/bin/kubectl
kubectl max --context admin@workshop -n "$NS" exec client -- echo max-recorded-call
k -n rknet-system logs -l app=maxlet --tail=3
# The session recorder writes actual upgraded stream bytes, not just request metadata.
found=false
for pod in $(k -n rknet-system get pods -l app=maxlet -o name); do
  if k -n rknet-system exec "$pod" -- sh -c 'grep -l '"'"'"direction":"server"'"'"' /archive/call-*.jsonl' 2>/dev/null; then found=true; fi
done
[[ "$found" == true ]]
echo 'PASS: authenticated MAX call succeeded and archived stream bytes'
