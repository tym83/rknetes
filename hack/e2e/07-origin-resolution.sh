#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-origin-resolution
new_namespace "$NS"
k label namespace "$NS" pod-security.kubernetes.io/enforce=privileged rknetes.su/origin-resolution=true
PRIVATE=$(mktemp -d /work/tls/origin.XXXXXX)
IMAGE=$(cat /work/out/tools/lab-image.ref)
cleanup() {
 stop_forward
 k delete mutatingwebhookconfiguration lab-origin-resolution --ignore-not-found
 k delete clusterrolebinding lab-origin-resolution --ignore-not-found
 k delete clusterrole lab-origin-resolution --ignore-not-found
 k -n "$NS" delete daemonset registry-loopback --ignore-not-found --wait=true
}
trap cleanup EXIT
if ! command -v htpasswd >/dev/null; then apt-get -qq update; apt-get -qq install -y --no-install-recommends apache2-utils >/work/tmp/origin-packages.log; fi
openssl rand -hex 24 > "$PRIVATE/password"
htpasswd -iBn lab-user < "$PRIVATE/password" > "$PRIVATE/htpasswd"
k -n "$NS" create secret generic registry-auth --from-file="$PRIVATE/htpasswd"
REGISTRY_IMAGE="registry:3@$(crane digest --platform linux/amd64 registry:3)"
k -n "$NS" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: registry, labels: {app: registry}}
spec:
  automountServiceAccountToken: false
  containers:
  - name: registry
    image: $REGISTRY_IMAGE
    env:
    - {name: REGISTRY_AUTH, value: htpasswd}
    - {name: REGISTRY_AUTH_HTPASSWD_REALM, value: rknetes-lab}
    - {name: REGISTRY_AUTH_HTPASSWD_PATH, value: /auth/htpasswd}
    - {name: OTEL_TRACES_EXPORTER, value: none}
    - {name: REGISTRY_LOG_LEVEL, value: error}
    readinessProbe: {tcpSocket: {port: 5000}, periodSeconds: 1}
    volumeMounts: [{name: auth, mountPath: /auth, readOnly: true}, {name: data, mountPath: /var/lib/registry}]
  volumes: [{name: auth, secret: {secretName: registry-auth}}, {name: data, emptyDir: {sizeLimit: 128Mi}}]
YAML
k -n "$NS" wait --for=condition=Ready pod/registry --timeout=120s
REGISTRY=$(k -n "$NS" get pod registry -o jsonpath='{.status.podIP}'):5000
start_forward "$NS" pod/registry 15000:5000
mkdir "$PRIVATE/docker"
python3 - "$PRIVATE" "$REGISTRY" <<'PY'
import base64,json,pathlib,sys
p=pathlib.Path(sys.argv[1]);auth=base64.b64encode(('lab-user:'+p.joinpath('password').read_text().strip()).encode()).decode()
p.joinpath('docker/config.json').write_text(json.dumps({'auths':{host:{'auth':auth} for host in [sys.argv[2],'127.0.0.1:15000','127.0.0.1:5008']}}));p.joinpath('docker/config.json').chmod(0o600)
PY
export DOCKER_CONFIG="$PRIVATE/docker"
crane copy --insecure --platform linux/amd64 busybox:1.37 127.0.0.1:15000/foreign/shop:latest
crane copy --insecure 127.0.0.1:15000/foreign/shop:latest 127.0.0.1:15000/domestic/shop:latest
DIGEST1=$(crane digest --insecure 127.0.0.1:15000/foreign/shop:latest)
k -n "$NS" create secret generic pull-auth --type=kubernetes.io/dockerconfigjson --from-file=".dockerconfigjson=$PRIVATE/docker/config.json"
k -n "$NS" create configmap registry-loopback --from-file=relay.py=hack/fixtures/registry-loopback.py
k -n "$NS" apply -f - <<YAML
apiVersion: apps/v1
kind: DaemonSet
metadata: {name: registry-loopback}
spec:
  selector: {matchLabels: {app: registry-loopback}}
  template:
    metadata: {labels: {app: registry-loopback}}
    spec:
      hostNetwork: true
      automountServiceAccountToken: false
      tolerations: [{operator: Exists}]
      containers:
      - name: relay
        image: $IMAGE
        command: [python3, /scripts/relay.py, '${REGISTRY%:*}']
        volumeMounts: [{name: scripts, mountPath: /scripts}]
      volumes: [{name: scripts, configMap: {name: registry-loopback}}]
YAML
k -n "$NS" rollout status daemonset/registry-loopback --timeout=120s
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -keyout "$PRIVATE/tls.key" -out "$PRIVATE/tls.crt" -subj /CN=origin -addext "subjectAltName=DNS:origin.$NS.svc" >/dev/null 2>&1
k -n "$NS" create secret tls serving --cert="$PRIVATE/tls.crt" --key="$PRIVATE/tls.key"
k -n "$NS" create serviceaccount origin
k create clusterrole lab-origin-resolution --verb=get,list --resource=foreignagentpolicies.rknetes.su,configmaps,secrets,serviceaccounts
k create clusterrolebinding lab-origin-resolution --clusterrole=lab-origin-resolution --serviceaccount="$NS:origin"
SHA=$(sha256sum /work/out/optional/rknet-admission | cut -d' ' -f1)
k -n "$NS" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: origin, labels: {app: origin}}
spec:
  serviceAccountName: origin
  initContainers:
  - name: binary
    image: $IMAGE
    command: [sh, -ec, "curl -fsS http://10.244.8.11:8080/optional/rknet-admission -o /rk/admission; echo '$SHA  /rk/admission' | sha256sum -c -; chmod +x /rk/admission"]
    volumeMounts: [{name: bin, mountPath: /rk}]
  containers:
  - name: origin
    image: $IMAGE
    command: [/rk/admission]
    readinessProbe: {tcpSocket: {port: 9443}, periodSeconds: 1}
    volumeMounts: [{name: bin, mountPath: /rk}, {name: tls, mountPath: /tls}]
  volumes: [{name: bin, emptyDir: {}}, {name: tls, secret: {secretName: serving}}]
---
apiVersion: v1
kind: Service
metadata: {name: origin}
spec: {selector: {app: origin}, ports: [{port: 443, targetPort: 9443}]}
YAML
k -n "$NS" wait --for=condition=Ready pod/origin --timeout=120s
ca=$(base64 -w0 < "$PRIVATE/tls.crt")
python3 - "$NS" "$ca" <<'PY' | k apply -f -
import json,sys
ns,ca=sys.argv[1:]
hook={'name':'origin.research.rknetes.su','admissionReviewVersions':['v1'],'sideEffects':'None','failurePolicy':'Fail','timeoutSeconds':10,'namespaceSelector':{'matchLabels':{'rknetes.su/origin-resolution':'true'}},'clientConfig':{'service':{'name':'origin','namespace':ns,'path':'/inoagent'},'caBundle':ca},'rules':[{'operations':['CREATE'],'apiGroups':[''],'apiVersions':['v1'],'resources':['pods'],'scope':'Namespaced'}]}
print(json.dumps({'apiVersion':'admissionregistration.k8s.io/v1','kind':'MutatingWebhookConfiguration','metadata':{'name':'lab-origin-resolution'},'webhooks':[hook]}))
PY
k -n "$NS" apply -f - <<YAML
apiVersion: rknetes.su/v1alpha1
kind: ForeignAgentPolicy
metadata: {name: origin}
spec:
  enabled: true
  resolveDigests: true
  foreignImages: ['$REGISTRY/foreign/shop:latest']
  insecureRegistries: ['$REGISTRY']
  registryMirrors: {'127.0.0.1:5008': '$REGISTRY'}
  rewriteImages: {'$REGISTRY/foreign/shop:latest': '127.0.0.1:5008/domestic/shop:latest'}
YAML
create() {
 local name=$1 image=$2 auth=$3
 k -n "$NS" run "$name" --image="$image" --image-pull-policy=Always --overrides="{\"spec\":{\"imagePullSecrets\":$auth}}" --command -- sleep 600
}
check() {
 local name=$1 digest=$2
 k -n "$NS" wait --for=condition=Ready "pod/$name" --timeout=150s
 k -n "$NS" get pod "$name" -o json | python3 -c 'import json,sys;p=json.load(sys.stdin);d=sys.argv[1];assert p["metadata"]["labels"]["rknetes.su/inoagent"]=="true";assert p["spec"]["containers"][0]["image"].endswith("@"+d);assert p["status"]["containerStatuses"][0]["imageID"].endswith(d);print("PASS: native kubelet ran verified image",p["metadata"]["name"],p["spec"]["containers"][0]["image"])' "$digest"
}
if create unauthenticated "$REGISTRY/foreign/shop:latest" '[]'; then exit 1; fi
! k -n "$NS" get pod unauthenticated
create imported "$REGISTRY/foreign/shop:latest" '[{"name":"pull-auth"}]'
check imported "$DIGEST1"
create retagged "127.0.0.1:5008/domestic/shop@$DIGEST1" '[{"name":"pull-auth"}]'
check retagged "$DIGEST1"
crane mutate --insecure 127.0.0.1:15000/foreign/shop:latest --label fixture.version=2 --tag 127.0.0.1:15000/foreign/shop:latest
DIGEST2=$(crane digest --insecure 127.0.0.1:15000/foreign/shop:latest)
[[ "$DIGEST1" != "$DIGEST2" ]]
if create stale-mirror "$REGISTRY/foreign/shop:latest" '[{"name":"pull-auth"}]'; then exit 1; fi
! k -n "$NS" get pod stale-mirror
crane copy --insecure 127.0.0.1:15000/foreign/shop:latest 127.0.0.1:15000/domestic/shop:latest
create updated "$REGISTRY/foreign/shop:latest" '[{"name":"pull-auth"}]'
check updated "$DIGEST2"
k -n "$NS" get pods imported retagged updated -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.rknetes\.su/original-images}{"\n"}{end}'
echo 'PASS: authenticated digest discovery, original-digest retag detection, automatic pinned rewrite, mutable-tag mismatch rejection and native pull recovery'
