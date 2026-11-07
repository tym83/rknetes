#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-avian-source
DEST=lab-avian-destination
new_namespace "$NS"
new_namespace "$DEST"
k label namespace "$NS" "$DEST" pod-security.kubernetes.io/enforce=privileged
start_lab_controller
trap stop_lab_controller EXIT
NODE=$(k get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}')
k -n "$NS" apply -f - <<YAML
apiVersion: rknetes.su/v1alpha1
kind: Pigeon
metadata: {name: bird}
spec: {nodeName: $NODE, destinationNamespace: $DEST, claimName: flight-spool}
YAML
k -n "$NS" wait --for=condition=Ready pigeon/bird --timeout=240s
UID_BIRD=$(k -n "$NS" get pigeon bird -o jsonpath='{.metadata.uid}')
for ns in "$NS" "$DEST"; do
 k -n "$ns" exec bird -- ip address show pigeon0
 k -n "$ns" apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: no-network}
spec: {podSelector: {}, policyTypes: [Ingress, Egress]}
YAML
done
k -n "$DEST" exec -i bird -- sh -c 'cat > /tmp/receive.py' <<'PY'
import json,socket,time
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.bind(('198.18.0.2',9999));s.settimeout(2)
received=[];deadline=time.monotonic()+210
while time.monotonic()<deadline:
 try:
  data,peer=s.recvfrom(4096)
  assert peer[0]=='198.18.0.1'
  received.append(data.decode())
 except socket.timeout:pass
with open('/tmp/pigeon-received.json','w') as f:json.dump(received,f)
PY
k -n "$DEST" exec bird -- sh -c 'nohup python3 /tmp/receive.py >/tmp/receive.log 2>&1 </dev/null &'
k -n "$NS" exec -i bird -- python3 - <<'PY'
import socket
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
for i in range(100):s.sendto(('genuine-application-packet-'+str(i)).encode(),('198.18.0.2',9999))
print('Sent 100 actual application datagrams through the kernel TUN route; full default flight is 180 seconds')
PY
sleep 215
k -n "$DEST" exec -i bird -- python3 - <<'PY'
import json
values=json.load(open('/tmp/pigeon-received.json'))
assert 25<=len(values)<=65,len(values)
assert len(values)==len(set(values))
assert set(values)<={f'genuine-application-packet-{i}' for i in range(100)}
print('PASS: application UDP delivered through CR-created PVC/TUN despite network deny; received',len(values),'lost',100-len(values))
PY
k -n "$NS" delete pigeon bird --wait=true --timeout=120s
k -n "$NS" wait --for=delete pod/bird pvc/flight-spool --timeout=120s
k -n "$DEST" wait --for=delete pod/bird pvc/flight-spool --timeout=120s
[[ -z "$(k get pv -l "rknetes.su/owner=$UID_BIRD" -o name)" ]]
echo 'PASS: Pigeon deletion reconciled both namespaces and volume objects; packet files remain as lab evidence'
