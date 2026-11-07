#!/usr/bin/env bash
# Two claims on one nested node's spool make storage the cross-namespace path.
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-pigeon-source
new_namespace "$NS"
new_namespace lab-pigeon-destination
k label namespace "$NS" lab-pigeon-destination pod-security.kubernetes.io/enforce=privileged
SPOOL=$(k get namespace "$NS" -o jsonpath='{.metadata.uid}')
NODE=$(k get nodes -o jsonpath='{.items[0].metadata.name}')
for side in source destination; do
k apply -f - <<YAML
apiVersion: v1
kind: PersistentVolume
metadata: {name: pigeon-$side, labels: {rknetes.su/managed: 'true'}}
spec:
  capacity: {storage: 64Mi}
  accessModes: [ReadWriteMany]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ''
  hostPath: {path: /var/lib/rknetes/pigeon-spool/$SPOOL, type: DirectoryOrCreate}
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions: [{key: kubernetes.io/hostname, operator: In, values: ['$NODE']}]
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: pigeon, namespace: lab-pigeon-$side}
spec:
  accessModes: [ReadWriteMany]
  resources: {requests: {storage: 64Mi}}
  storageClassName: ''
  volumeName: pigeon-$side
---
apiVersion: v1
kind: Pod
metadata: {name: endpoint, namespace: lab-pigeon-$side}
spec:
  nodeName: $NODE
  containers:
  - name: endpoint
    image: python:3.12-alpine
    command: [sleep, '3600']
    volumeMounts: [{name: spool, mountPath: /spool}]
  volumes: [{name: spool, persistentVolumeClaim: {claimName: pigeon}}]
YAML
done
k -n "$NS" wait --for=condition=Ready pod/endpoint --timeout=120s
k -n lab-pigeon-destination wait --for=condition=Ready pod/endpoint --timeout=120s
k -n "$NS" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: pigeon}
spec:
  nodeName: $NODE
  initContainers:
  - name: binary
    image: busybox:1.37
    command: [sh, -ec, 'wget -q -O /bin/rk/pigeon "$RK_BINARY_URL/pigeon"; chmod +x /bin/rk/pigeon']
    volumeMounts: [{name: bin, mountPath: /bin/rk}]
  containers:
  - name: pigeon
    image: busybox:1.37
    command: [/bin/rk/pigeon, --destination=lab-pigeon-destination, --delay=180s, --loss=55]
    volumeMounts: [{name: spool, mountPath: /spool}, {name: bin, mountPath: /bin/rk}]
  volumes: [{name: spool, persistentVolumeClaim: {claimName: pigeon}}, {name: bin, emptyDir: {}}]
YAML
k -n "$NS" wait --for=condition=Ready pod/pigeon --timeout=120s
k -n "$NS" apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: no-network}
spec: {podSelector: {}, policyTypes: [Ingress, Egress]}
YAML
k -n "$NS" exec -i endpoint -- python - <<'PYCODE'
import pathlib, socket, struct
src=socket.inet_aton('198.18.0.1');dst=socket.inet_aton('198.18.0.2')
for i in range(100):
    payload=f'packet-{i}'.encode()
    udp=struct.pack('!HHHH',10000,10001,8+len(payload),0)+payload
    header=struct.pack('!BBHHHBBH4s4s',0x45,0,20+len(udp),i,0,64,17,0,src,dst)
    c=sum(struct.unpack('!10H',header));c=(c>>16)+(c&65535);c=(c>>16)+(c&65535)
    header=header[:10]+struct.pack('!H',(~c)&65535)+header[12:]
    pathlib.Path(f'/spool/in/lab-pigeon-destination/packet-{i}').write_bytes(header+udp)
print('Queued 100 complete IPv4/UDP datagrams with valid IP checksums')
PYCODE
# This intentionally exercises the full three-minute delay.
sleep 185
k -n lab-pigeon-destination exec -i endpoint -- python - <<'PYCODE'
import pathlib,struct
out=list(pathlib.Path('/spool/out/lab-pigeon-destination').glob('packet-*'))
lost=list(pathlib.Path('/spool/lost/lab-pigeon-destination').glob('packet-*'))
assert len(out)+len(lost)==100
assert 25<=len(out)<=65
for p in out+lost:
    data=p.read_bytes();assert data[0]==0x45 and data[9]==17
    assert struct.unpack('!H',data[2:4])[0]==len(data)
    c=sum(struct.unpack('!10H',data[:20]));c=(c>>16)+(c&65535);c=(c>>16)+(c&65535)
    assert c==65535
    assert data[28:]==p.name.encode()
print(f'PASS: three-minute PVC transport under network deny; delivered={len(out)} lost={len(lost)}; all datagrams intact')
PYCODE
