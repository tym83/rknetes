#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-dependency-graph
new_namespace "$NS"
fixture shop
fixture sms
fixture captcha
k -n "$NS" expose pod shop --port=8080
SMS=$(k -n "$NS" get pod sms -o jsonpath='{.status.podIP}')
CAPTCHA=$(k -n "$NS" get pod captcha -o jsonpath='{.status.podIP}')
k -n "$NS" apply -f - <<'YAML'
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata: {name: captcha}
spec:
  endpointSelector: {matchLabels: {app: sms}}
  enableDefaultDeny: {ingress: false, egress: false}
  egressDeny: [{toEndpoints: [{matchLabels: {app: captcha}}]}]
YAML
k -n "$NS" exec shop -- wget -q -T 3 -O - "http://$SMS:8080"
denied() { ! k -n "$NS" exec sms -- wget -q -T 3 -O - "http://$CAPTCHA:8080"; }
wait_until denied
start_forward kube-system service/hubble-relay 14245:80
trap stop_forward EXIT
graph() {
 /work/out/optional/rknetesctl --kubeconfig "$KUBECONFIG" -n "$NS" --hubble 127.0.0.1:14245 why shop > /work/tmp/dependency-graph.txt
 python3 - <<'PY'
from pathlib import Path
s=Path('/work/tmp/dependency-graph.txt').read_text().split('Observed root dependency graph',1)[1].split('End observed root graph',1)[0]
assert 'lab-dependency-graph/shop' in s
assert 'lab-dependency-graph/sms' in s and 'FORWARDED=' in s
assert 'lab-dependency-graph/captcha [DROPPED=' in s,s
PY
}
wait_until graph
cat /work/tmp/dependency-graph.txt
/work/out/optional/rknetesctl --kubeconfig "$KUBECONFIG" -n "$NS" --hubble 127.0.0.1:14245 why never-observed | grep 'NO_OBSERVATION'
echo 'PASS: root-specific observed transitive graph exposes the blocked second hop and marks absent evidence unknown'
