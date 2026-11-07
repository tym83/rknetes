#!/usr/bin/env bash
# Exercise the production 20-minute / 80-minute schedule without clock changes.
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-escalation-soak
new_namespace "$NS"
mapfile -t nodes < <(k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
[[ ${#nodes[@]} -ge 2 ]]
for name in telegram neighbour remote; do
  node=${nodes[0]}; [[ "$name" != remote ]] || node=${nodes[1]}
  k -n "$NS" run "$name" --image=busybox:1.37 --overrides="{\"spec\":{\"nodeName\":\"$node\"}}" --command -- sh -c 'mkdir -p /tmp/www; echo ok > /tmp/www/index.html; httpd -f -p 8080 -h /tmp/www'
done
k -n "$NS" run client --image=busybox:1.37 --overrides="{\"spec\":{\"nodeName\":\"${nodes[1]}\"}}" --command -- sleep 7200
k -n "$NS" wait --for=condition=Ready pods --all --timeout=120s
TARGET=$(k -n "$NS" get pod telegram -o jsonpath='{.status.podIP}')
NEIGHBOUR=$(k -n "$NS" get pod neighbour -o jsonpath='{.status.podIP}')
REMOTE=$(k -n "$NS" get pod remote -o jsonpath='{.status.podIP}')
NODE_CIDR=$(k get node "${nodes[0]}" -o jsonpath='{.spec.podCIDR}')
probe "http://$TARGET:8080"
probe "http://$NEIGHBOUR:8080"
probe "http://$REMOTE:8080"
k -n "$NS" apply -f - <<'YAML'
apiVersion: rknetes.su/v1alpha1
kind: ReestrEntry
metadata: {name: telegram}
spec: {podName: telegram, escalate: true}
YAML
created=$(k -n "$NS" get reestrentry telegram -o jsonpath='{.metadata.creationTimestamp}')
start=$(python3 -c 'import datetime,sys;print(int(datetime.datetime.fromisoformat(sys.argv[1].replace("Z","+00:00")).timestamp()))' "$created")
k -n "$NS" wait --for=condition=Applied reestrentry/telegram --timeout=60s
wait_until assert_blocked "http://$TARGET:8080"
has_cidr() { k -n "$NS" get reestrentry telegram -o jsonpath='{.status.cidrs}' | grep -Fq "$1"; }
while true; do
  elapsed=$(( $(date +%s) - start ))
  printf '%s elapsed=%ss ' "$(date -u +%FT%TZ)" "$elapsed"
  if (( elapsed < 1190 )); then
    ! has_cidr "$NODE_CIDR"
    probe "http://$NEIGHBOUR:8080"
    probe "http://$REMOTE:8080"
    echo 'IP stage; both innocent applications reachable'
  elif (( elapsed >= 1210 && elapsed < 4790 )); then
    has_cidr "$NODE_CIDR"
    ! has_cidr 10.42.0.0/16
    assert_blocked "http://$NEIGHBOUR:8080"
    probe "http://$REMOTE:8080"
    echo 'node stage; neighbour denied, remote reachable'
  elif (( elapsed >= 4810 )); then
    has_cidr 10.42.0.0/16
    # The status records the pool CIDR when the policy is written; Cilium applies
    # it shortly after. Allow the same bounded wait as every other enforcement check.
    wait_until assert_blocked "http://$NEIGHBOUR:8080"
    wait_until assert_blocked "http://$REMOTE:8080"
    echo 'pool stage; both innocent applications denied'
    break
  else
    echo 'transition window'
  fi
  sleep 30
done
k -n "$NS" annotate pod telegram rknetes.su/ready-to-counter-terrorism=true
wait_until probe "http://$NEIGHBOUR:8080"
wait_until probe "http://$REMOTE:8080"
k -n "$NS" get reestrentry telegram -o yaml
echo 'PASS: real default 20/80-minute schedule, collateral packet denial and amnesty'
