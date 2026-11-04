#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-throttle
new_namespace "$NS"
fixture payment-controller
SERVER_NODE=$(k -n "$NS" get pod payment-controller -o jsonpath='{.spec.nodeName}')
CLIENT_NODE=$(k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep -v "^$SERVER_NODE$" | head -1)
k -n "$NS" run client --image=busybox:1.37 --overrides="{\"spec\":{\"nodeName\":\"$CLIENT_NODE\"}}" --command -- sleep 3600
k -n "$NS" wait --for=condition=Ready pod/client --timeout=120s
IP=$(k -n "$NS" get pod payment-controller -o jsonpath='{.status.podIP}')
k -n "$NS" exec payment-controller -- sh -c 'dd if=/dev/zero of=/tmp/www/blob bs=1024 count=512 2>/dev/null'
start=$(date +%s)
probe "http://$IP:8080/blob" >/dev/null
baseline=$(( $(date +%s)-start ))
k -n "$NS" apply -f - <<'YAML'
apiVersion: rknetes.su/v1alpha1
kind: ThrottlePolicy
metadata: {name: twitter}
spec: {pattern: 't.co', bandwidth: 256k, mode: Замедление}
YAML
k -n "$NS" wait --for=condition=Applied throttlepolicy/twitter --timeout=60s
[[ "$(k -n "$NS" get pod payment-controller -o jsonpath='{.metadata.annotations.kubernetes\.io/egress-bandwidth}')" == 256k ]]
sleep 5
start=$(date +%s)
k -n "$NS" exec client -- wget -q -T 60 -O /dev/null "http://$IP:8080/blob"
throttled=$(( $(date +%s)-start ))
printf "Measured baseline=%ss throttled=%ss\n" "$baseline" "$throttled"
[[ $throttled -ge 10 && $throttled -gt $((baseline+5)) ]]
k -n "$NS" get events --field-selector reason=NotRelated -o name | grep -q event
printf 'PASS: t.co matched payment-controller; baseline=%ss throttled=%ss\n' "$baseline" "$throttled"
