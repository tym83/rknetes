#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-watch-resources
GATEWAY_NS=lab-watch-gateway
new_namespace "$NS"
new_namespace "$GATEWAY_NS"
k label namespace "$NS" rknetes.su/independent-controller=true
IMAGE=$(cat /work/out/tools/lab-image.ref)
PRIVATE=$(mktemp -d /work/tls/watch-resources.XXXXXX)
trap 'k delete clusterrolebinding lab-watch-resources --ignore-not-found; k delete clusterrole lab-watch-resources --ignore-not-found' EXIT
python3 - "$PRIVATE" <<'PY'
import base64,json,pathlib,subprocess,sys
p=pathlib.Path(sys.argv[1]);p.chmod(0o700)
c=json.loads(subprocess.check_output(['kubectl','--context','admin@workshop','config','view','--raw','--minify','-o','json']))
for value,name in [(c['users'][0]['user']['client-certificate-data'],'client.crt'),(c['users'][0]['user']['client-key-data'],'client.key'),(c['clusters'][0]['cluster']['certificate-authority-data'],'native.crt')]:
 path=p/name;path.write_bytes(base64.b64decode(value));path.chmod(0o600)
(p/'gateway.crt').write_bytes(pathlib.Path('/work/tls/watch/tls.crt').read_bytes())
PY
k -n "$NS" create secret generic client-keys --from-file="$PRIVATE"
k -n "$NS" create configmap test-script --from-file=watch.py=hack/fixtures/watch-resources.py
k -n "$GATEWAY_NS" create secret tls serving --cert="$RK_TLS_DIR/watch/tls.crt" --key="$RK_TLS_DIR/watch/tls.key"
k -n "$GATEWAY_NS" create serviceaccount office
k apply -f - <<'YAML'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: {name: lab-watch-resources}
rules:
- {apiGroups: ['*'], resources: ['*'], verbs: [get, list, watch]}
- {apiGroups: [rknetes.su], resources: [bloggerregistrations, bloggerregistrations/status], verbs: [create, patch]}
- {apiGroups: [authorization.k8s.io], resources: [subjectaccessreviews], verbs: [create]}
YAML
k create clusterrolebinding lab-watch-resources --clusterrole lab-watch-resources --serviceaccount="$GATEWAY_NS:office"
SHA=$(sha256sum /work/out/optional/watch-office | cut -d' ' -f1)
k -n "$GATEWAY_NS" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: gateway}
spec:
  serviceAccountName: office
  initContainers:
  - name: binary
    image: $IMAGE
    command: [sh, -ec, "curl -fsS http://10.244.8.11:8080/optional/watch-office -o /rk/watch; echo '$SHA  /rk/watch' | sha256sum -c -; chmod +x /rk/watch"]
    volumeMounts: [{name: bin, mountPath: /rk}]
  containers:
  - name: watch
    image: $IMAGE
    command: [/rk/watch]
    readinessProbe: {tcpSocket: {port: 9443}, periodSeconds: 1}
    volumeMounts: [{name: bin, mountPath: /rk}, {name: tls, mountPath: /tls}]
  volumes: [{name: bin, emptyDir: {}}, {name: tls, secret: {secretName: serving}}]
YAML
k -n "$GATEWAY_NS" wait --for=condition=Ready pod/gateway --timeout=120s
GATEWAY=$(k -n "$GATEWAY_NS" get pod gateway -o jsonpath='{.status.podIP}')
k -n "$NS" create configmap channel --from-literal=message=observed
k -n "$NS" create configmap neighbour --from-literal=message=also-observed
k -n "$NS" label configmaps channel neighbour channel=example
k -n "$NS" create deployment channel --image=busybox:1.37 --replicas=0
k -n "$NS" label deployment channel channel=example
k -n "$NS" apply -f - <<'YAML'
apiVersion: rknetes.su/v1alpha1
kind: TunnelProfile
metadata: {name: channel, labels: {channel: example}}
spec: {protocolLadder: [OpenVPN]}
YAML
for tuple in configmaps:cm-channel deployments.apps:deployment-channel tunnelprofiles.rknetes.su:custom-channel configmaps:late-channel; do
 IFS=: read -r resource name <<< "$tuple"
 object=channel; [[ "$name" != late-channel ]] || object=late
 k -n "$NS" apply -f - <<YAML
apiVersion: rknetes.su/v1alpha1
kind: BloggerRegistration
metadata: {name: $name}
spec: {resource: $resource, name: $object, threshold: 1, registered: false}
YAML
done
k -n "$NS" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: client, labels: {app: publication-client}}
spec:
  automountServiceAccountToken: false
  containers:
  - name: client
    image: $IMAGE
    command: [sleep, '1800']
    volumeMounts: [{name: keys, mountPath: /keys, readOnly: true}, {name: script, mountPath: /test, readOnly: true}]
  volumes: [{name: keys, secret: {secretName: client-keys}}, {name: script, configMap: {name: test-script}}]
YAML
k -n "$NS" wait --for=condition=Ready pod/client --timeout=120s
k -n "$NS" exec client -- python3 /test/watch.py "$GATEWAY" native
k -n "$NS" apply -f - <<'YAML'
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata: {name: public-api-route}
spec:
  endpointSelector: {matchLabels: {app: publication-client}}
  enableDefaultDeny: {ingress: false, egress: false}
  egressDeny: [{toEntities: [kube-apiserver]}, {toCIDR: [10.96.0.1/32]}]
YAML
sleep 3
k -n "$NS" exec client -- sh -c "nohup sh -c 'python3 /test/watch.py $GATEWAY > /tmp/watch-results 2>&1; echo \$? > /tmp/watch-exit' >/dev/null 2>&1 </dev/null &"
stage() { [[ "$(k -n "$NS" exec client -- cat /tmp/watch-stage 2>/dev/null)" == "$1" ]]; }
for name in cm-channel deployment-channel custom-channel; do
 wait_until stage "$name-blocked"
 k -n "$NS" patch bloggerregistration "$name" --type merge -p '{"spec":{"registered":true}}'
done
wait_until stage late-watch-ready
k -n "$NS" create configmap late --from-literal=message=created-after-subscribe
k -n "$NS" label configmap late late=example
wait_until stage late-channel-blocked
k -n "$NS" patch bloggerregistration late-channel --type merge -p '{"spec":{"registered":true}}'
wait_until stage complete
k -n "$NS" exec client -- cat /tmp/watch-results
[[ "$(k -n "$NS" exec client -- cat /tmp/watch-exit)" == 0 ]]
k -n "$NS" get bloggerregistrations -o json | python3 -c 'import json,sys;objects=json.load(sys.stdin)["items"];assert len(objects)==4;assert all(x["status"]["observedConcurrentWatches"]==2 for x in objects);print("PASS: four persisted audience peaks=2, core/apps/custom resources and late object")'
k -n "$NS" get configmap channel
echo 'PASS: native administrator remains readable; selected client must use the authenticated public gateway'
