#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-drill
new_namespace "$NS"
fixture foreign
client
IP=$(k -n "$NS" get pod foreign -o jsonpath='{.status.podIP}')
probe "http://$IP:8080"
k -n "$NS" apply -f - <<'YAML'
apiVersion: rknetes.su/v1alpha1
kind: SovereigntyDrill
metadata: {name: quarterly}
spec: {enabled: true, foreignSelector: {app: foreign}}
YAML
k -n "$NS" wait --for=condition=Ready sovereigntydrill/quarterly --timeout=60s
wait_until assert_blocked "http://$IP:8080"
echo 'PASS: a lab foreign service is unreachable while the drill reports success'
