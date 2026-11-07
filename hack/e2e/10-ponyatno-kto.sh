#!/usr/bin/env bash
# cluster-admin-ponyatno-kto may do anything, except touch the TSPU agent.
# All refusals use server-side dry run: admission runs, nothing on the node changes.
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-ponyatno-kto
new_namespace "$NS"
as=(--as=ponyatno-kto --as-group=rknetes:ponyatno-kto)

echo "RBAC verdict for the highest role:"
k auth can-i '*' '*' --all-namespaces "${as[@]}"
k auth can-i delete daemonsets.apps -n rknet-system "${as[@]}"

k -n "$NS" run ordinary --image=busybox:1.37 --command -- sleep 600
k -n "$NS" wait --for=condition=Ready pod/ordinary --timeout=120s
k -n "$NS" delete pod ordinary --wait=true "${as[@]}"
echo 'PASS: the highest role deletes an ordinary pod'

pod=$(k -n rknet-system get pod -l app=tspu -o jsonpath='{.items[0].metadata.name}')
refused() {
  local out
  if out=$("$@" 2>&1); then echo "unexpectedly allowed: $out" >&2; return 1; fi
  echo "$out"
  [[ "$out" == *"Прав cluster-admin-ponyatno-kto на ТСПУ недостаточно. Чьих достаточно — не указано."* ]]
}
refused k -n rknet-system delete pod "$pod" --dry-run=server "${as[@]}"
refused k -n rknet-system delete daemonset tspu --dry-run=server "${as[@]}"
refused k -n rknet-system label pod "$pod" rknetes.su/inspected=true --dry-run=server "${as[@]}"
echo 'PASS: RBAC says yes, the TSPU agent says no'

echo "Somebody else's rights are enough:"
k -n rknet-system delete daemonset tspu --dry-run=server
k -n rknet-system get daemonset tspu -o name
echo 'PASS: the same request without the group is admitted; whose rights those are is not stated'
