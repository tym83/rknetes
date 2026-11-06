#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-payload-archive
new_namespace "$NS"
k label namespace "$NS" pod-security.kubernetes.io/enforce=privileged rknetes.su/archive-test=true
start_lab_controller
cleanup(){ stop_lab_controller; k delete mutatingwebhookconfiguration lab-archive --ignore-not-found; k delete clusterrolebinding lab-archive --ignore-not-found; k delete clusterrole lab-archive --ignore-not-found; }
trap cleanup EXIT
IMAGE=$(cat /work/out/tools/lab-image.ref)
PRIVATE=$(mktemp -d /work/tls/archive.XXXXXX)
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -keyout "$PRIVATE/tls.key" -out "$PRIVATE/tls.crt" -subj /CN=archive -addext "subjectAltName=DNS:admission.$NS.svc" >/dev/null 2>&1
k -n "$NS" create secret tls serving --cert="$PRIVATE/tls.crt" --key="$PRIVATE/tls.key"
k -n "$NS" create serviceaccount admission
k create clusterrole lab-archive --verb=get,list --resource=archivepolicies.rknetes.su,configmaps
k create clusterrolebinding lab-archive --clusterrole=lab-archive --serviceaccount="$NS:admission"
ADMISSION_SHA=$(sha256sum /work/out/optional/rknet-admission | cut -d' ' -f1)
k -n "$NS" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: admission, labels: {app: admission}}
spec:
  serviceAccountName: admission
  initContainers:
  - name: binary
    image: $IMAGE
    command: [sh, -ec, "curl -fsS http://10.244.8.11:8080/optional/rknet-admission -o /rk/admission; echo '$ADMISSION_SHA  /rk/admission' | sha256sum -c -; chmod +x /rk/admission"]
    volumeMounts: [{name: bin, mountPath: /rk}]
  containers:
  - name: admission
    image: $IMAGE
    command: [/rk/admission]
    readinessProbe: {tcpSocket: {port: 9443}, periodSeconds: 1}
    volumeMounts: [{name: bin, mountPath: /rk}, {name: tls, mountPath: /tls}]
  volumes: [{name: bin, emptyDir: {}}, {name: tls, secret: {secretName: serving}}]
---
apiVersion: v1
kind: Service
metadata: {name: admission}
spec: {selector: {app: admission}, ports: [{port: 443, targetPort: 9443}]}
YAML
k -n "$NS" wait --for=condition=Ready pod/admission --timeout=120s
CA=$(base64 -w0 "$PRIVATE/tls.crt")
k apply -f - <<YAML
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata: {name: lab-archive}
webhooks:
- name: archive.lab.rknetes.su
  admissionReviewVersions: [v1]
  sideEffects: None
  failurePolicy: Fail
  namespaceSelector: {matchLabels: {rknetes.su/archive-test: 'true'}}
  clientConfig: {service: {name: admission, namespace: $NS, path: /archive}, caBundle: $CA}
  rules: [{operations: [CREATE], apiGroups: [''], apiVersions: [v1], resources: [pods]}]
YAML
k -n "$NS" create configmap scripts --from-file=server.py=hack/fixtures/archive-server.py --from-file=control-plane.sh=hack/fixtures/archive-control-plane.sh
k -n "$NS" apply -f - <<'YAML'
apiVersion: rknetes.su/v1alpha1
kind: ArchivePolicy
metadata: {name: payload}
spec: {selector: {app: archived}, volumeName: archive, retentionDays: 180, maxBytes: 16777216, capturePayload: true}
---
apiVersion: rknetes.su/v1alpha1
kind: ArchivePolicy
metadata: {name: full-disk}
spec: {retentionDays: 180, maxBytes: 536870912, capturePayload: true}
YAML
sleep 4
k -n "$NS" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: receiver, labels: {app: archived}}
spec:
  containers:
  - name: server
    image: $IMAGE
    command: [python3, /scripts/server.py]
    volumeMounts: [{name: scripts, mountPath: /scripts}, {name: archive, mountPath: /archive}]
  volumes: [{name: scripts, configMap: {name: scripts}}, {name: archive, emptyDir: {sizeLimit: 32Mi}}]
YAML
k -n "$NS" wait --for=condition=Ready pod/receiver --timeout=120s
k -n "$NS" run client --image="$IMAGE" --command -- sleep 1800
k -n "$NS" wait --for=condition=Ready pod/client --timeout=120s
RECEIVER=$(k -n "$NS" get pod receiver -o jsonpath='{.status.podIP}')
for _ in $(seq 1 5); do k -n "$NS" exec client -- curl -fsS "http://$RECEIVER:8080"; sleep 2; done
payload_recorded(){ k -n "$NS" exec receiver -c server -- sh -c 'grep -a -q RKARCHIVE /archive/*/*.pcap && test -n "$(find /archive -name "*.jsonl")"'; }
wait_until payload_recorded
k -n "$NS" exec receiver -c server -- python3 -c 'import pathlib,json,os,time;root=next(pathlib.Path("/archive").iterdir());flows=[json.loads(x) for p in root.glob("*.jsonl") for x in p.read_text().splitlines()];assert any(f["source"]["namespace"]=="lab-payload-archive" and f["destination"]["namespace"]=="lab-payload-archive" for f in flows);old=root/"expired.pcap";old.write_bytes(b"expired");os.utime(old,(time.time()-181*86400,)*2);(root/"retained.pcap").write_bytes(b"retained");print("PASS: exact application payload in PCAP and actual Hubble endpoint metadata")'
sleep 4
k -n "$NS" exec receiver -c server -- sh -c 'test -z "$(find /archive -name expired.pcap)"; test -n "$(find /archive -name retained.pcap)"'
echo 'PASS: 180-day retention removes only an expired controlled fixture; recent capture remains'
TOOLS_SHA=$(sha256sum /work/out/tools/archive-tools.tar.gz | cut -d' ' -f1)
ARCHIVE_SHA=$(sha256sum /work/out/optional/archive-agent | cut -d' ' -f1)
k -n "$NS" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: control-plane, labels: {app: disposable-control-plane}}
spec:
  terminationGracePeriodSeconds: 15
  initContainers:
  - name: binary
    image: $IMAGE
    command: [sh, -ec, "curl -fsS http://10.244.8.11:8080/tools/archive-tools.tar.gz -o /rk/tools.tgz; echo '$TOOLS_SHA  /rk/tools.tgz' | sha256sum -c -; curl -fsS http://10.244.8.11:8080/optional/archive-agent -o /rk/archive-agent; echo '$ARCHIVE_SHA  /rk/archive-agent' | sha256sum -c -; chmod +x /rk/archive-agent"]
    volumeMounts: [{name: bin, mountPath: /rk}]
  containers:
  - name: control-plane
    image: $IMAGE
    command: [bash, -ec, 'mkdir -p /opt/archive-tools; tar -xzf /rk/tools.tgz -C /opt/archive-tools; export PATH=/opt/archive-tools/usr/local/bin:$PATH LD_LIBRARY_PATH=/opt/archive-tools/lib/x86_64-linux-gnu:/opt/archive-tools/usr/lib/x86_64-linux-gnu; exec bash /scripts/control-plane.sh']
    securityContext: {privileged: true}
    resources: {requests: {cpu: '100m', memory: 512Mi}, limits: {cpu: '2', memory: 2Gi}}
    env:
    - {name: POD_NAMESPACE, valueFrom: {fieldRef: {fieldPath: metadata.namespace}}}
    - {name: POD_NAME, valueFrom: {fieldRef: {fieldPath: metadata.name}}}
    volumeMounts: [{name: bin, mountPath: /rk}, {name: scripts, mountPath: /scripts}, {name: disk, mountPath: /private-disk}]
  volumes: [{name: bin, emptyDir: {}}, {name: scripts, configMap: {name: scripts}}, {name: disk, emptyDir: {sizeLimit: 300Mi}}]
YAML
k -n "$NS" wait --for=condition=Ready pod/control-plane --timeout=120s
api(){ k -n "$NS" exec control-plane -- curl -ksS --cert /tmp/cp/tls.crt --key /tmp/cp/tls.key --max-time 8 "$@"; }
ready(){ [[ "$(api https://127.0.0.1:6444/readyz 2>/dev/null)" == ok ]]; }
wait_until ready
api -X POST -H 'Content-Type: application/json' -d '{"apiVersion":"v1","kind":"ConfigMap","metadata":{"name":"before","namespace":"default"},"data":{"proof":"persisted-before-disk-full"}}' https://127.0.0.1:6444/api/v1/namespaces/default/configmaps | python3 -c 'import json,sys;assert json.load(sys.stdin)["metadata"]["name"]=="before";print("PASS: disposable API wrote etcd before capture filled disk")'
CONTROL=$(k -n "$NS" get pod control-plane -o jsonpath='{.status.podIP}')
k -n "$NS" exec client -- sh -c "nohup python3 -c 'import socket,time;s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);end=time.time()+90;data=b\"RKARCHIVE disk pressure \"*50
while time.time()<end:s.sendto(data,(\"$CONTROL\",8081));time.sleep(0.0001)' >/tmp/sender.log 2>&1 </dev/null &"
full(){ [[ "$(k -n "$NS" get archivepolicy full-disk -o jsonpath='{.status.conditions[0].reason}')" == StorageExhausted ]]; }
wait_until full
k -n "$NS" exec client -- pkill -f 'RKARCHIVE disk pressure' || true
k -n "$NS" exec control-plane -- sh -c 'df -B1 /disk; du -sb /disk/archive /disk/etcd; tail -3 /tmp/archive.log; kill $(cat /tmp/archive.pid)'
k -n "$NS" exec -i control-plane -- python3 - <<'PYTEST'
import json,ssl,urllib.request,urllib.error
context=ssl.create_default_context(cafile='/tmp/cp/tls.crt');context.load_cert_chain('/tmp/cp/tls.crt','/tmp/cp/tls.key')
for i in range(64):
 data=json.dumps({'apiVersion':'v1','kind':'ConfigMap','metadata':{'name':'pressure-'+str(i),'namespace':'default'},'data':{'payload':'x'*800000}}).encode()
 request=urllib.request.Request('https://127.0.0.1:6444/api/v1/namespaces/default/configmaps',data=data,headers={'Content-Type':'application/json'})
 try:
  with urllib.request.urlopen(request,context=context,timeout=8) as response:assert response.status==201
 except (urllib.error.HTTPError,TimeoutError,OSError) as error:
  print('PASS: real disposable API write failed on shared full filesystem after',i,'completed writes:',type(error).__name__);break
else:raise AssertionError('all bounded API writes succeeded despite the full filesystem')
PYTEST
k -n "$NS" exec control-plane -- sh -c 'grep -q "no space left on device" /tmp/etcd.log'
k -n "$NS" exec control-plane -- sh -c 'tail -12 /tmp/etcd.log; rm -f /disk/archive/*.pcap /disk/archive/*.jsonl; kill $(cat /tmp/etcd.pid) 2>/dev/null || true; sleep 2; nohup etcd --data-dir=/disk/etcd --listen-client-urls=http://127.0.0.1:2379 --advertise-client-urls=http://127.0.0.1:2379 --listen-peer-urls=http://127.0.0.1:2380 --initial-advertise-peer-urls=http://127.0.0.1:2380 --initial-cluster=default=http://127.0.0.1:2380 --quota-backend-bytes=1073741824 --max-wals=1 >/tmp/etcd-recovery.log 2>&1 </dev/null &'
wait_until ready
api https://127.0.0.1:6444/api/v1/namespaces/default/configmaps/before | python3 -c 'import json,sys;assert json.load(sys.stdin)["data"]["proof"]=="persisted-before-disk-full"'
api -X POST -H 'Content-Type: application/json' -d '{"apiVersion":"v1","kind":"ConfigMap","metadata":{"name":"recovered","namespace":"default"},"data":{"proof":"after"}}' https://127.0.0.1:6444/api/v1/namespaces/default/configmaps | python3 -c 'import json,sys;assert json.load(sys.stdin)["metadata"]["name"]=="recovered";print("PASS: disk recovery preserved original etcd data and accepted a new native API write")'
k -n "$NS" delete pod control-plane --wait=true
[[ "$(k get --raw /readyz)" == ok ]]
echo 'PASS: original nested API stayed ready; loop device detached with the disposable Pod'
