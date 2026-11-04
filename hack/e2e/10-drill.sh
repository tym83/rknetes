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
k -n "$NS" patch sovereigntydrill quarterly --type merge -p '{"spec":{"enabled":false}}'
wait_until probe "http://$IP:8080"
echo 'PASS: a lab foreign service is unreachable during the successful drill; disabling it restores packet delivery'
