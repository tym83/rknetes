#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-werewolf
new_namespace "$NS"
fixture smuggler
client
# An unused lab Service address makes the destination unambiguous. No outside IP
# or outer Service is involved: this prefix belongs to the nested Service range.
IP=10.110.77.77
assert_blocked "http://$IP:8080"
k -n "$NS" apply -f - <<YAML
apiVersion: rknetes.su/v1alpha1
kind: Werewolf
metadata: {name: redirect}
spec: {address: $IP, selector: {app: smuggler}, port: 8080}
YAML
k -n "$NS" wait --for=condition=Applied werewolf/redirect --timeout=60s
wait_until probe "http://$IP:8080"
echo 'PASS: creating a Service externalIPs claim captured traffic to a previously unreachable lab address'
