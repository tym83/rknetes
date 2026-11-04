#!/usr/bin/env bash
# Accelerate the same time-based controller path; prove both collateral scopes.
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-escalation
new_namespace "$NS"
mapfile -t nodes < <(k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
[[ ${#nodes[@]} -ge 2 ]]
for name in telegram neighbour remote; do
  node=${nodes[0]}; [[ "$name" != remote ]] || node=${nodes[1]}
  k -n "$NS" run "$name" --image=busybox:1.37 --overrides="{\"spec\":{\"nodeName\":\"$node\"}}" --command -- sh -c 'mkdir -p /tmp/www; echo ok > /tmp/www/index.html; httpd -f -p 8080 -h /tmp/www'
done
k -n "$NS" run client --image=busybox:1.37 --overrides="{\"spec\":{\"nodeName\":\"${nodes[1]}\"}}" --command -- sleep 3600
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
spec: {podName: telegram, escalate: true, nodeAfterSeconds: 15, poolAfterSeconds: 35}
YAML
k -n "$NS" wait --for=condition=Applied reestrentry/telegram --timeout=60s
wait_until assert_blocked "http://$TARGET:8080"
probe "http://$NEIGHBOUR:8080"
probe "http://$REMOTE:8080"
has_cidr() { k -n "$NS" get reestrentry telegram -o jsonpath='{.status.cidrs}' | grep -Fq "$1"; }
wait_until has_cidr "$NODE_CIDR"
wait_until assert_blocked "http://$NEIGHBOUR:8080"
probe "http://$REMOTE:8080"
wait_until has_cidr 10.42.0.0/16
wait_until assert_blocked "http://$REMOTE:8080"
k -n "$NS" annotate pod telegram rknetes.su/ready-to-counter-terrorism=true
wait_until probe "http://$NEIGHBOUR:8080"
wait_until probe "http://$REMOTE:8080"
echo 'PASS: IP-only, node-CIDR and pool-CIDR stages caused measured collateral failures; amnesty restored both innocent applications'
