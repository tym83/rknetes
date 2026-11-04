#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-byte-boundaries
new_namespace "$NS"
k -n rknet-system exec daemonset/tspu -- /rk/tspu --self-test
k -n "$NS" apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata: {name: foreign}
spec:
  initContainers:
  - name: binary
    image: busybox:1.37
    command: [sh, -ec, 'wget -q -O /rk/lab-server http://10.244.8.11:8080/optional/lab-server; chmod +x /rk/lab-server']
    volumeMounts: [{name: bin, mountPath: /rk}]
  containers:
  - name: app
    image: busybox:1.37
    command: [/rk/lab-server, --chunk, '1000']
    volumeMounts: [{name: bin, mountPath: /rk}]
  volumes: [{name: bin, emptyDir: {}}]
---
apiVersion: v1
kind: Pod
metadata: {name: reader, labels: {app: reader}}
spec:
  containers: [{name: reader, image: python:3.12-alpine, command: [sleep, '3600']}]
YAML
k -n "$NS" wait --for=condition=Ready pod/foreign pod/reader --timeout=180s
IP=$(k -n "$NS" get pod foreign -o jsonpath='{.status.podIP}')
k -n "$NS" apply -f - <<YAML
apiVersion: rknetes.su/v1alpha1
kind: SovereignBytePolicy
metadata: {name: foreign}
spec: {selector: {app: reader}, foreignCIDRs: ['$IP/32'], limit: 16384}
YAML
check() {
 k -n "$NS" exec -i reader -- python - "$IP" <<'PY'
import concurrent.futures,socket,sys,urllib.request
ip=sys.argv[1]
def transfer(_):
 with socket.create_connection((ip,8081),timeout=3) as s:
  s.settimeout(3);n=0;stalled=False
  try:
   while n<65536:
    chunk=s.recv(65536)
    if not chunk:break
    n+=len(chunk)
  except socket.timeout:stalled=True
  assert stalled and n==16000,(n,stalled)
  return n
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:counts=list(executor.map(transfer,range(8)))
assert urllib.request.urlopen('http://'+ip+':8080/healthz',timeout=3).read()==b'ok'
print('Eight independent concurrent streams stalled at packet boundaries:',counts,'health remains green')
PY
}
wait_until check
k -n "$NS" patch sovereignbytepolicy foreign --type merge -p '{"spec":{"foreignCIDRs":["10.244.8.0/24"]}}'
rejected() { k -n "$NS" get sovereignbytepolicy foreign -o json | grep 'outside the nested lab range'; }
wait_until rejected
restored() {
 k -n "$NS" exec -i reader -- python - "$IP" <<'PY'
import socket,sys
with socket.create_connection((sys.argv[1],8081),timeout=3) as s:
 s.settimeout(3);n=0
 while n<65536:
  chunk=s.recv(65536)
  if not chunk:break
  n+=len(chunk)
assert n==65536,n
print('Rejected out-of-lab policy removed its former filter; actual payload',n)
PY
}
wait_until restored
echo 'PASS: kernel sequence wrap/retransmission tests, concurrent packet-boundary limits and safe invalid-policy cleanup'
