#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-byte-policy
new_namespace "$NS"
: "${RK_BINARY_URL:?}"
k -n "$NS" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: foreign, labels: {app: foreign}}
spec:
  initContainers:
  - name: binary
    image: busybox:1.37
    command: [sh, -ec, "wget -q -O /rk/lab-server '$RK_BINARY_URL/lab-server'; chmod +x /rk/lab-server"]
    volumeMounts: [{name: bin, mountPath: /rk}]
  containers:
  - name: app
    image: busybox:1.37
    command: [/rk/lab-server]
    readinessProbe: {httpGet: {path: /healthz, port: 8080}, periodSeconds: 1}
    volumeMounts: [{name: bin, mountPath: /rk}]
  volumes: [{name: bin, emptyDir: {}}]
YAML
reader() {
 k -n "$NS" run reader --image=python:3.12-alpine --labels=app=reader --command -- sleep 3600
 k -n "$NS" wait --for=condition=Ready pod/reader --timeout=180s
}
reader
k -n "$NS" wait --for=condition=Ready pod/foreign --timeout=180s
IP=$(k -n "$NS" get pod foreign -o jsonpath='{.status.podIP}')
transfer() {
 k -n "$NS" exec -i reader -- python - "$IP" "$1" <<'PY'
import socket,sys,urllib.request
ip,expected=sys.argv[1],int(sys.argv[2])
assert urllib.request.urlopen('http://'+ip+':8080/healthz',timeout=3).read()==b'ok'
with socket.create_connection((ip,8081),timeout=3) as s:
 s.settimeout(3);data=b'';stalled=False
 try:
  while len(data)<65536:
   b=s.recv(65536)
   if not b:break
   data+=b
 except socket.timeout:stalled=True
 assert len(data)==expected,(len(data),expected)
 assert stalled==(expected<65536),(stalled,expected)
print('actual TCP payload:',len(data),'stalled:',stalled)
PY
}
transfer 65536
k -n "$NS" apply -f - <<YAML
apiVersion: rknetes.su/v1alpha1
kind: SovereignBytePolicy
metadata: {name: foreign}
spec:
  selector: {app: reader}
  foreignCIDRs: ['$IP/32']
  limit: 16384
YAML
wait_until transfer 16384
OLD_UID=$(k -n "$NS" get pod reader -o jsonpath='{.metadata.uid}')
k -n "$NS" delete pod reader --wait=true
reader
[[ "$(k -n "$NS" get pod reader -o jsonpath='{.metadata.uid}')" != "$OLD_UID" ]]
wait_until transfer 16384
k -n "$NS" get sovereignbytepolicy foreign -o json
k -n "$NS" delete sovereignbytepolicy foreign
wait_until transfer 65536
k -n rknet-system logs -l app=tspu --prefix --tail=30
echo 'PASS: CR-managed node agent attaches to new Pod network namespaces and policy deletion restores full transfers'
