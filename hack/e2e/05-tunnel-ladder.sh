#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-tunnel-client
SERVERS=lab-tunnel-server
DEST=lab-tunnel-pigeon
for ns in "$NS" "$SERVERS" "$DEST"; do new_namespace "$ns"; k label namespace "$ns" pod-security.kubernetes.io/enforce=privileged; done
IMAGE=$(cat /work/out/tools/lab-image.ref)
PRIVATE=/work/tls/tunnel-ladder
python3 hack/fixtures/tunnels.py "$PRIVATE"
for role in server client; do
 ns=$NS; [[ "$role" != server ]] || ns=$SERVERS
 k -n "$ns" create secret generic protocol-keys --from-file="$PRIVATE/$role"
 k -n "$ns" create configmap protocol-scripts --from-file="start.sh=hack/fixtures/tunnel-$role.sh"
done
SHA=$(sha256sum /work/out/optional/tunnel-probe | cut -d' ' -f1)
pod() {
 local ns=$1 name=$2 server=${3:-127.0.0.1}
 k -n "$ns" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: $name, labels: {app: $name}}
spec:
  automountServiceAccountToken: false
  initContainers:
  - name: binary
    image: $IMAGE
    command: [sh, -ec, "curl -fsS http://10.244.8.11:8080/optional/tunnel-probe -o /rk/tunnel-probe; echo '$SHA  /rk/tunnel-probe' | sha256sum -c -; chmod +x /rk/tunnel-probe"]
    volumeMounts: [{name: bin, mountPath: /rk}]
  containers:
  - name: protocols
    image: $IMAGE
    command: [bash, /scripts/start.sh]
    env: [{name: SERVER_IP, value: '$server'}]
    securityContext: {privileged: true}
    resources: {requests: {cpu: 50m, memory: 128Mi}, limits: {cpu: '2', memory: 512Mi}}
    volumeMounts: [{name: bin, mountPath: /rk}, {name: keys, mountPath: /keys, readOnly: true}, {name: scripts, mountPath: /scripts, readOnly: true}, {name: runtime, mountPath: /runtime}]
  volumes: [{name: bin, emptyDir: {}}, {name: keys, secret: {secretName: protocol-keys}}, {name: scripts, configMap: {name: protocol-scripts}}, {name: runtime, emptyDir: {}}]
YAML
 k -n "$ns" wait --for=condition=Ready "pod/$name" --timeout=150s
}
pod "$SERVERS" gosuslugi
SERVER=$(k -n "$SERVERS" get pod gosuslugi -o jsonpath='{.status.podIP}')
pod "$NS" agent "$SERVER"
probe_protocol() {
 k -n "$NS" exec agent -- curl -fsS "http://127.0.0.1:7777/probe?protocol=$1" | python3 -c 'import json,sys; p=json.load(sys.stdin); print(p); assert p["success"] and p["bytes"]>0'
}
for protocol in OpenVPN WireGuard Shadowsocks VLESSReality Gosuslugi DNS ICMP; do wait_until probe_protocol "$protocol"; done
echo 'PASS: all seven protocol drivers transferred real HTTP application bytes'
k label namespace "$NS" rknetes.su/independent-controller=true --overwrite
start_controller() {
 /work/out/optional/rknet-controller --kubeconfig "$KUBECONFIG" --context admin@workshop --namespace "$NS" --metrics-listen 127.0.0.1:19090 > /work/tmp/controller-$NS.log 2>&1 &
 lab_controller=$!
}
start_controller
trap stop_lab_controller EXIT
NODE=$(k get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}')
k -n "$NS" apply -f - <<YAML
apiVersion: rknetes.su/v1alpha1
kind: Pigeon
metadata: {name: carrier}
spec: {nodeName: $NODE, destinationNamespace: $DEST, observeTraffic: true}
---
apiVersion: rknetes.su/v1alpha1
kind: TunnelProfile
metadata: {name: escape}
spec:
  agentPodName: agent
  pigeonRef: carrier
  protocolLadder: [OpenVPN, WireGuard, Shadowsocks, VLESSReality, Gosuslugi, DNS, ICMP, Pigeon]
YAML
active() { [[ "$(k -n "$NS" get tunnelprofile escape -o jsonpath='{.status.activeProtocol}')" == "$1" ]] && [[ "$(k -n "$NS" get tunnelprofile escape -o jsonpath='{.status.conditions[0].status}')" == True ]]; }
wait_until active OpenVPN
ports=()
deny() {
 ports+=("$1:$2")
 python3 - "$SERVER" "${ports[@]}" <<'PY' | k -n "$NS" apply -f -
import json,sys
rules=[]
for pair in sys.argv[2:]:
 port,protocol=pair.split(':')
 rule={'toCIDR':[sys.argv[1]+'/32']}
 if protocol=='ICMP':rule['icmps']=[{'fields':[{'family':'IPv4','type':8}]}]
 else:rule['toPorts']=[{'ports':[{'port':port,'protocol':protocol}]}]
 rules.append(rule)
print(json.dumps({'apiVersion':'cilium.io/v2','kind':'CiliumNetworkPolicy','metadata':{'name':'protocol-blocks'},'spec':{'endpointSelector':{'matchLabels':{'app':'agent'}},'enableDefaultDeny':{'ingress':False,'egress':False},'egressDeny':rules}}))
PY
}
for transition in '1194:UDP:WireGuard' '51820:UDP:Shadowsocks' '8388:TCP:VLESSReality' '8443:TCP:Gosuslugi' '8444:TCP:DNS' '53:UDP:ICMP'; do
 IFS=: read -r port transport next <<< "$transition"
 deny "$port" "$transport"
 wait_until active "$next"
 echo "PASS: actual transport denied; controller selected $next after a real failed probe"
done
deny 8 ICMP
bird_ready() { [[ "$(k -n "$NS" get pigeon carrier -o jsonpath='{.status.readyEndpoints}')" == 2 ]]; }
wait_until bird_ready
k -n "$DEST" exec -i carrier -- sh -c 'cat >/tmp/receive.py' <<'PY'
import socket,time,json
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.bind(('198.18.0.2',9999));s.settimeout(2)
got=[];end=time.monotonic()+210
while time.monotonic()<end:
 try:got.append(s.recvfrom(4096)[0].decode())
 except socket.timeout:pass
json.dump(got,open('/tmp/received.json','w'))
PY
k -n "$DEST" exec carrier -- sh -c 'nohup python3 /tmp/receive.py >/tmp/receive.log 2>&1 </dev/null &'
for ns in "$NS" "$DEST"; do
 k -n "$ns" apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: carrier-isolation}
spec:
  podSelector: {matchExpressions: [{key: rknetes.su/owner, operator: Exists}]}
  policyTypes: [Ingress, Egress]
  ingress: [{ports: [{protocol: TCP, port: 7778}]}]
YAML
done
k -n "$NS" exec -i carrier -- python3 - <<'PY'
import socket
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
for i in range(100):s.sendto(('ladder-'+str(i)).encode(),('198.18.0.2',9999))
PY
sleep 215
wait_until active Pigeon
k -n "$DEST" exec -i carrier -- python3 - <<'PY'
import json
got=json.load(open('/tmp/received.json'));assert 25<=len(got)<=65,len(got)
assert len(got)==len(set(got));assert set(got)<={f'ladder-{i}' for i in range(100)}
print('PASS: Pigeon fallback delivered',len(got),'actual application datagrams after180seconds')
PY
[[ "$(k -n "$NS" get cm vpn-counters -o jsonpath='{.data.blocked}')" == 7 ]]
stop_lab_controller
start_controller
sleep 8
curl -fsS http://127.0.0.1:19090/metrics | tee /work/tmp/vpn-metrics.txt
grep -qx 'rknetes_vpn_blocked_total 7' /work/tmp/vpn-metrics.txt
! grep -q 'working_total' /work/tmp/vpn-metrics.txt
wait_until active Pigeon
k -n "$NS" get tunnelprofile/escape pigeon/carrier -o json
k -n "$NS" delete tunnelprofile/escape pigeon/carrier --wait=true --timeout=120s
echo 'PASS: persistent counter survives restart without double counting; no working-tunnel metric exists'
