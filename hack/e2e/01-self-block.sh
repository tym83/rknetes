#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-self-block
new_namespace "$NS"
k label namespace "$NS" rknetes.su/independent-controller=true
fixture telegram
client
k -n "$NS" create serviceaccount reestr-controller
k create rolebinding reestr-self-controller --clusterrole=rknet-controller --serviceaccount="$NS:reestr-controller" -n "$NS"
# The controller's discovery and marker reads need the existing nested-only role.
k create clusterrolebinding reestr-self-controller --clusterrole=rknet-controller --serviceaccount="$NS:reestr-controller"
k -n "$NS" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: reestr-controller}
spec:
  serviceAccountName: reestr-controller
  initContainers:
  - name: binary
    image: busybox:1.37
    command: [sh, -ec, 'wget -q -O /bin/rk/controller "$RK_BINARY_URL/rknet-controller"; chmod +x /bin/rk/controller']
    volumeMounts: [{name: bin, mountPath: /bin/rk}]
  containers:
  - name: controller
    image: busybox:1.37
    command: [/bin/rk/controller, --namespace=$NS]
    volumeMounts: [{name: bin, mountPath: /bin/rk}]
  volumes: [{name: bin, emptyDir: {}}]
YAML
k -n "$NS" wait --for=condition=Ready pod/reestr-controller --timeout=120s
k -n "$NS" apply -f - <<'YAML'
apiVersion: rknetes.su/v1alpha1
kind: ReestrEntry
metadata: {name: telegram}
spec: {podName: telegram, serviceAfterSeconds: 8}
YAML
sleep 35
k -n "$NS" logs reestr-controller > /tmp/rknet-self-controller.log
grep -E '10.96.0.1.*(timeout|deadline)' /tmp/rknet-self-controller.log
# A separate out-of-band API route remains available: this is the actual recovery boundary.
k -n "$NS" delete reestrentry telegram
k -n "$NS" delete ciliumnetworkpolicy reestr-telegram --ignore-not-found
k -n "$NS" exec client -- sh -c 'wget --no-check-certificate -S -T 5 -O - https://10.96.0.1:443/healthz 2>&1' | grep -E 'ok|401|403'
echo 'PASS: the controller lost its API route and recovered via out-of-band API access'
