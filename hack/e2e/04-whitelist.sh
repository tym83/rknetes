#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-whitelist
new_namespace "$NS"
fixture gosuslugi
fixture smuggler
client
k -n "$NS" expose pod gosuslugi --port=8080
GOS=$(k -n "$NS" get svc gosuslugi -o jsonpath='{.spec.clusterIP}')
BAD=$(k -n "$NS" get pod smuggler -o jsonpath='{.status.podIP}')
k -n "$NS" apply -f - <<'YAML'
apiVersion: rknetes.su/v1alpha1
kind: SociallySignificantResource
metadata: {name: gosuslugi}
spec:
  serviceName: gosuslugi
  selector: {app: gosuslugi}
  approved: true
  dependencies: [sms, captcha]
---
apiVersion: rknetes.su/v1alpha1
kind: WhitelistMode
metadata: {name: mobile}
spec: {enabled: true, integrity: false}
YAML
k -n "$NS" wait --for=condition=Whitelisted socialresources/gosuslugi --timeout=60s
wait_until probe "http://$GOS:8080"
wait_until assert_blocked "http://$BAD:8080"
k -n "$NS" label pod smuggler app=gosuslugi --overwrite
wait_until probe "http://$BAD:8080"
k -n "$NS" label pod smuggler app=smuggler --overwrite
k -n "$NS" apply -f - <<YAML
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: smuggled
  labels: {kubernetes.io/service-name: gosuslugi, endpointslice.kubernetes.io/managed-by: smuggler}
addressType: IPv4
ports: [{port: 8080, protocol: TCP}]
endpoints: [{addresses: ["$BAD"], conditions: {ready: true}}]
YAML
k -n "$NS" patch whitelistmode mobile --type merge -p '{"spec":{"integrity":true}}'
k -n "$NS" wait --for=condition=Whitelisted=False socialresources/gosuslugi --timeout=60s
wait_until assert_blocked "http://$GOS:8080"
rknetesctl --kubeconfig "$KUBECONFIG" -n "$NS" why gosuslugi
echo 'PASS: label impersonation restored reachability; manual EndpointSlice caused whole-service denial'
