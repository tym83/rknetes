#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-api-streams
GATEWAY_NS=lab-api-gateway
new_namespace "$NS"
new_namespace "$GATEWAY_NS"
IMAGE=$(cat /work/out/tools/lab-image.ref)
PRIVATE=$(mktemp -d /work/tls/api-streams.XXXXXX)
cleanup() {
 k delete clusterrolebinding lab-api-gateway --ignore-not-found
 k delete clusterrole lab-api-gateway --ignore-not-found
 k delete crd widgets.lab.rknetes.su --ignore-not-found --wait=false
}
trap cleanup EXIT
k -n "$GATEWAY_NS" create serviceaccount gateway
k apply -f - <<YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: {name: lab-api-gateway}
rules:
- {apiGroups: [''], resources: [namespaces, configmaps, pods, pods/log], verbs: [get]}
- {apiGroups: [authorization.k8s.io], resources: [subjectaccessreviews], verbs: [create]}
- {apiGroups: [apiextensions.k8s.io], resources: [customresourcedefinitions], verbs: [get, create, update, delete]}
YAML
k create clusterrolebinding lab-api-gateway --clusterrole lab-api-gateway --serviceaccount="$GATEWAY_NS:gateway"
k -n "$GATEWAY_NS" create secret tls serving --cert="$RK_TLS_DIR/maxlet/tls.crt" --key="$RK_TLS_DIR/maxlet/tls.key"
MAX_SHA=$(sha256sum /work/out/optional/maxlet | cut -d' ' -f1)
k -n "$GATEWAY_NS" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: gateway, labels: {app: gateway}}
spec:
  serviceAccountName: gateway
  initContainers:
  - name: binary
    image: $IMAGE
    command: [sh, -ec, "curl -fsS http://10.244.8.11:8080/optional/maxlet -o /rk/maxlet; echo '$MAX_SHA  /rk/maxlet' | sha256sum -c -; chmod +x /rk/maxlet"]
    volumeMounts: [{name: bin, mountPath: /rk}]
  containers:
  - name: gateway
    image: $IMAGE
    command: [/rk/maxlet, --lab-definitions, --events=false, --archive, /archive]
    readinessProbe: {tcpSocket: {port: 9443}, periodSeconds: 1}
    volumeMounts: [{name: bin, mountPath: /rk}, {name: tls, mountPath: /tls, readOnly: true}, {name: archive, mountPath: /archive}]
  volumes: [{name: bin, emptyDir: {}}, {name: tls, secret: {secretName: serving}}, {name: archive, emptyDir: {}}]
YAML
k -n "$GATEWAY_NS" wait --for=condition=Ready pod/gateway --timeout=120s
IP=$(k -n "$GATEWAY_NS" get pod gateway -o jsonpath='{.status.podIP}')
python3 - "$PRIVATE" "$IP" <<'PY'
import json,pathlib,subprocess,sys,base64,random
p=pathlib.Path(sys.argv[1]);p.chmod(0o700)
c=json.loads(subprocess.check_output(['kubectl','--context','admin@workshop','config','view','--raw','--minify','-o','json']))
c['clusters'][0]['cluster']['server']='https://'+sys.argv[2]+':9443'
c['clusters'][0]['cluster']['certificate-authority-data']=base64.b64encode(pathlib.Path('/work/tls/maxlet/tls.crt').read_bytes()).decode()
c['clusters'][0]['cluster']['tls-server-name']='maxlet.rknet-system.svc'
(p/'config').write_text(json.dumps(c));(p/'config').chmod(0o600)
description=base64.b64encode(random.Random(42).randbytes(150000)).decode()
crd={'apiVersion':'apiextensions.k8s.io/v1','kind':'CustomResourceDefinition','metadata':{'name':'widgets.lab.rknetes.su','labels':{'rknetes.su/lab':'true'}},'spec':{'group':'lab.rknetes.su','scope':'Namespaced','names':{'kind':'Widget','plural':'widgets','singular':'widget'},'versions':[{'name':'v1','served':True,'storage':True,'schema':{'openAPIV3Schema':{'type':'object','description':description,'properties':{'spec':{'type':'object','x-kubernetes-preserve-unknown-fields':True}}}}}]}}
(p/'large.json').write_text(json.dumps(crd))
PY
k -n "$NS" create secret generic client-config --from-file="$PRIVATE/config"
k -n "$NS" create configmap large-definition --from-file="$PRIVATE/large.json"
cp /work/bin/kubectl /work/out/tools/kubectl
CLIENT_SHA=$(sha256sum /work/out/tools/kubectl | cut -d' ' -f1)
k -n "$NS" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: client, labels: {app: api-client}}
spec:
  automountServiceAccountToken: false
  initContainers:
  - name: binary
    image: $IMAGE
    command: [sh, -ec, "curl -fsS http://10.244.8.11:8080/tools/kubectl -o /rk/kubectl; echo '$CLIENT_SHA  /rk/kubectl' | sha256sum -c -; chmod +x /rk/kubectl"]
    volumeMounts: [{name: bin, mountPath: /rk}]
  containers:
  - name: client
    image: $IMAGE
    command: [sleep, '3600']
    volumeMounts: [{name: bin, mountPath: /rk}, {name: client, mountPath: /client, readOnly: true}, {name: definition, mountPath: /definition, readOnly: true}]
  volumes: [{name: bin, emptyDir: {}}, {name: client, secret: {secretName: client-config}}, {name: definition, configMap: {name: large-definition}}]
YAML
k -n "$NS" run logger --image=busybox:1.37 --command -- sh -c 'head -c131072 /dev/urandom | base64; sleep 3600'
k -n "$NS" wait --for=condition=Ready pod/client pod/logger --timeout=120s
remote() { k -n "$NS" exec client -- /rk/kubectl --kubeconfig=/client/config --context admin@workshop --request-timeout=8s "$@"; }
logs() { k -n "$NS" exec client -- sh -c '/rk/kubectl --kubeconfig=/client/config --context admin@workshop --request-timeout=8s -n lab-api-streams logs logger >/tmp/logs'; }
logs
EXPECTED=$(k -n "$NS" exec client -- sha256sum /tmp/logs | cut -d' ' -f1)
remote create --validate=false -f /definition/large.json
k wait --for=condition=Established crd/widgets.lab.rknetes.su --timeout=60s
k delete crd widgets.lab.rknetes.su --wait=true
k -n "$NS" apply -f - <<YAML
apiVersion: rknetes.su/v1alpha1
kind: SovereignBytePolicy
metadata: {name: streams}
spec: {selector: {app: api-client}, foreignCIDRs: ['$IP/32'], limit: 16384}
YAML
sleep 5
remote get --raw=/version
if logs; then echo 'unexpected complete log stream under byte limit'; exit 1; fi
PARTIAL=$(k -n "$NS" exec client -- wc -c /tmp/logs | awk '{print $1}')
[[ "$PARTIAL" -gt 0 && "$PARTIAL" -lt 16384 ]]
echo "PASS: genuine kubectl logs stalled with $PARTIAL application bytes; TLS overhead and whole-packet drops consume part of the16384-byte transport budget"
if remote create --validate=false -f /definition/large.json; then echo 'unexpected large definition creation'; exit 1; fi
! k get crd widgets.lab.rknetes.su
remote get --raw=/version
k -n "$NS" get pod logger -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
k -n "$NS" delete sovereignbytepolicy streams
sleep 4
logs
ACTUAL=$(k -n "$NS" exec client -- sha256sum /tmp/logs | cut -d' ' -f1)
[[ "$ACTUAL" == "$EXPECTED" ]]
remote create --validate=false -f /definition/large.json
k wait --for=condition=Established crd/widgets.lab.rknetes.su --timeout=60s
echo 'PASS: full log hash and actual large CRD creation recovered after byte policy deletion; readiness and small discovery remained green'
