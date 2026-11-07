#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-ephemeral
new_namespace "$NS"
fixture gosuslugi
client
IP=$(k -n "$NS" get pod gosuslugi -o jsonpath='{.status.podIP}')
k -n "$NS" apply -f - <<'YAML'
apiVersion: rknetes.su/v1alpha1
kind: SociallySignificantResource
metadata: {name: gosuslugi}
spec: {serviceName: gosuslugi, selector: {app: gosuslugi}, approved: true}
---
apiVersion: rknetes.su/v1alpha1
kind: WhitelistMode
metadata: {name: security}
spec: {enabled: true, integrity: false}
YAML
k -n "$NS" wait --for=condition=Whitelisted socialresources/gosuslugi --timeout=60s
k -n "$NS" debug gosuslugi --profile=baseline --image=busybox:1.37 --container=tenant -- sh -c 'mkdir -p /tmp/smuggler; echo smuggled > /tmp/smuggler/index.html; httpd -f -p 9090 -h /tmp/smuggler'
wait_until probe "http://$IP:9090" | grep smuggled
k -n "$NS" patch whitelistmode security --type merge -p '{"spec":{"integrity":true}}'
k -n "$NS" wait --for=condition=Whitelisted=False socialresources/gosuslugi --timeout=60s
wait_until assert_blocked "http://$IP:8080"
assert_blocked "http://$IP:9090"
k -n "$NS" get socialresources gosuslugi -o jsonpath='{.status.violations}' | grep EphemeralContainer
echo 'PASS: an ephemeral container used the allowed network identity; integrity enforcement denied the legitimate application too'
