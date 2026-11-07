#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-16k
new_namespace "$NS"
k label namespace "$NS" pod-security.kubernetes.io/enforce=privileged
: "${RK_BINARY_URL:?private builder binary URL required}"
k -n "$NS" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: foreign}
spec:
  initContainers:
  - name: tspu
    image: nicolaka/netshoot:v0.14
    securityContext: {privileged: true}
    command: [sh, -ec]
    args:
    - |
      wget -q -O /rk/lab-server '$RK_BINARY_URL/lab-server'
      wget -q -O /rk/sovereign-16k.o '$RK_BINARY_URL/sovereign-16k.o'
      chmod +x /rk/lab-server
      tc qdisc replace dev eth0 clsact
      tc filter replace dev eth0 egress pref 32000 bpf direct-action obj /rk/sovereign-16k.o sec tc
    volumeMounts: [{name: bin, mountPath: /rk}]
  containers:
  - name: app
    image: busybox:1.37
    command: [/rk/lab-server]
    readinessProbe: {httpGet: {path: /healthz, port: 8080}, periodSeconds: 1}
    volumeMounts: [{name: bin, mountPath: /rk}]
  volumes: [{name: bin, emptyDir: {}}]
---
apiVersion: v1
kind: Pod
metadata: {name: reader}
spec:
  containers: [{name: reader, image: python:3.12-alpine, command: [sleep, '3600']}]
YAML
k -n "$NS" wait --for=condition=Ready pod/foreign pod/reader --timeout=240s
IP=$(k -n "$NS" get pod foreign -o jsonpath='{.status.podIP}')
k -n "$NS" exec -i reader -- python - "$IP" <<'PY'
import socket, sys, urllib.request
ip=sys.argv[1]
assert urllib.request.urlopen('http://'+ip+':8080/healthz').read()==b'ok'
s=socket.create_connection((ip,8081), timeout=5);s.settimeout(3)
data=b'';stalled=False
try:
    while True:
        chunk=s.recv(4096)
        if not chunk: break
        data+=chunk
except socket.timeout:
    stalled=True
assert stalled, 'expected a live socket stalled before EOF'
assert len(data)==16384, f'actual payload before stall: {len(data)}'
assert urllib.request.urlopen('http://'+ip+':8080/healthz').read()==b'ok'
print('PASS: eBPF delivered 16384 bytes then stalled; HTTP readiness still works')
PY
