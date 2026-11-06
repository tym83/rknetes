#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source /work/src/rknetes/hack/research/native-root.sh
NS=${RK_ARTIFACT_CLIENTS:-lab-artifact-clients}
SERVERS=${RK_ARTIFACT_SERVERS:-lab-artifact-services}
new_namespace "$NS"
new_namespace "$SERVERS"
k label namespace "$NS" pod-security.kubernetes.io/enforce=privileged
start_lab_controller
trap stop_lab_controller EXIT
IMAGE=$(cat /work/out/tools/lab-image.ref)
[[ "$IMAGE" == 10.244.8.11:5000/rknetes-lab-tools@sha256:* ]] || exit 2
fixture_dir=${RK_ARTIFACT_DIRECTORY:-/work/tmp/artifact-fixture}
case "$fixture_dir" in /work/tmp/artifact-fixture|/work/tmp/composed-artifacts) ;; *) exit 2 ;; esac
rm -rf -- "$fixture_dir"
mkdir -p "$fixture_dir" /work/out/fixtures
app_args=()
if [[ -n "${RK_ARTIFACT_APPLICATION:-}" ]]; then app_args=(--application "$RK_ARTIFACT_APPLICATION"); fi
python3 hack/fixtures/artifacts.py --directory "$fixture_dir" --prepare "$RK_NATIVE_ROOT/bin/busybox" --variant "${RK_ARTIFACT_VARIANT:-}" "${app_args[@]}"
if [[ "${RK_ARTIFACT_TWO_VERSIONS:-}" == 1 ]]; then
 python3 hack/fixtures/artifacts.py --directory "$fixture_dir/second" --prepare "$RK_NATIVE_ROOT/bin/busybox" --variant "${RK_ARTIFACT_VARIANT:-}-second" "${app_args[@]}"
 cp "$fixture_dir"/second/sha256-* "$fixture_dir/"
 cp "$fixture_dir/second/manifest.json" "$fixture_dir/manifest-2.json"
 rm -rf -- "$fixture_dir/second"
fi
ARCHIVE_NAME=artifacts-$SERVERS.tar.gz
tar -czf /work/out/fixtures/$ARCHIVE_NAME -C "$fixture_dir" .
SHA=$(sha256sum /work/out/fixtures/$ARCHIVE_NAME | cut -d' ' -f1)
k -n "$SERVERS" create configmap artifact-server --from-file=artifacts.py=hack/fixtures/artifacts.py
server() {
 local name=$1 role=$2 cdn=${3:-}
 k -n "$SERVERS" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: $name, labels: {app: $name}}
spec:
  automountServiceAccountToken: false
  initContainers:
  - name: files
    image: $IMAGE
    command: [sh, -ec, "curl -fsS http://10.244.8.11:8080/fixtures/$ARCHIVE_NAME -o /data/input.tar.gz; echo '$SHA  /data/input.tar.gz' | sha256sum -c -; tar -xzf /data/input.tar.gz -C /data; rm /data/input.tar.gz"]
    volumeMounts: [{name: data, mountPath: /data}]
  containers:
  - name: server
    image: $IMAGE
    command: [python3, /script/artifacts.py, --directory, /data, --role, $role]
    env: [{name: CDN_URL, value: '$cdn'}]
    readinessProbe: {httpGet: {path: /healthz, port: 8080}, periodSeconds: 1}
    volumeMounts: [{name: data, mountPath: /data}, {name: script, mountPath: /script}]
  volumes: [{name: data, emptyDir: {sizeLimit: 64Mi}}, {name: script, configMap: {name: artifact-server}}]
YAML
 k -n "$SERVERS" wait --for=condition=Ready "pod/$name" --timeout=180s
}
server cdn cdn
CDN=http://$(k -n "$SERVERS" get pod cdn -o jsonpath='{.status.podIP}'):8080
CDN_ORIGIN=$CDN
if [[ "${RK_ARTIFACT_CDN_PROXY:-}" == 1 ]]; then
 server relay relay "$CDN"
 CDN=http://$(k -n "$SERVERS" get pod relay -o jsonpath='{.status.podIP}'):8080
fi
server registry registry "$CDN"
REGISTRY=http://$(k -n "$SERVERS" get pod registry -o jsonpath='{.status.podIP}'):8080
k -n "$SERVERS" exec registry -- curl -fsS "$REGISTRY/index.yaml" > /work/tmp/artifact-index.yaml
k -n "$SERVERS" create configmap upstream-index --from-file=index.yaml=/work/tmp/artifact-index.yaml
GOSHRAN_SHA=$(sha256sum /work/out/optional/goshran | cut -d' ' -f1)
k -n "$SERVERS" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: goshran, labels: {app: goshran}}
spec:
  automountServiceAccountToken: false
  initContainers:
  - name: binary
    image: $IMAGE
    command: [sh, -ec, "curl -fsS http://10.244.8.11:8080/optional/goshran -o /rk/goshran; echo '$GOSHRAN_SHA  /rk/goshran' | sha256sum -c -; chmod +x /rk/goshran"]
    volumeMounts: [{name: bin, mountPath: /rk}]
  containers:
  - name: goshran
    image: $IMAGE
    command: [/rk/goshran, --listen, ':8080', --upstream, '$REGISTRY', --index, /index/index.yaml]
    readinessProbe: {httpGet: {path: /healthz, port: 8080}, periodSeconds: 1}
    volumeMounts: [{name: bin, mountPath: /rk}, {name: index, mountPath: /index}]
  volumes: [{name: bin, emptyDir: {}}, {name: index, configMap: {name: upstream-index}}]
YAML
k -n "$SERVERS" wait --for=condition=Ready pod/goshran --timeout=180s
GOSHRAN=$(k -n "$SERVERS" get pod goshran -o jsonpath='{.status.podIP}'):8080
reader() {
 k -n "$NS" delete pod client --ignore-not-found --wait=true
 k -n "$NS" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: client, labels: {app: artifact-client}}
spec:
  automountServiceAccountToken: false
  containers:
  - name: runtime
    image: $IMAGE
    securityContext: {privileged: true}
    command: [sh, -ec]
    args:
    - |
      containerd --root /runtime/root --state /runtime/state --address /runtime/containerd.sock >/runtime/daemon.log 2>&1 &
      daemon=\$!
      trap 'kill \$daemon; wait \$daemon' EXIT
      wait \$daemon
    readinessProbe: {exec: {command: [ctr, --address, /runtime/containerd.sock, version]}, periodSeconds: 1}
    resources: {requests: {cpu: 100m, memory: 128Mi}, limits: {cpu: '2', memory: 512Mi}}
    volumeMounts: [{name: runtime, mountPath: /runtime}]
  volumes: [{name: runtime, emptyDir: {sizeLimit: 256Mi}}]
YAML
 k -n "$NS" wait --for=condition=Ready pod/client --timeout=180s
}
pull() { k -n "$NS" exec client -- timeout 25s ctr --address /runtime/containerd.sock --namespace lab images pull --local --plain-http --snapshotter native "$GOSHRAN/lab/shop:1"; }
chart() { k -n "$NS" exec client -- timeout 20s helm pull shop --repo "http://$GOSHRAN" --destination /tmp; }
if [[ "${RK_ARTIFACT_PREPARE_ONLY:-}" == 1 ]]; then return 0 2>/dev/null || exit 0; fi
reader
pull
chart
k -n "$NS" exec client -- sha256sum /tmp/shop-0.1.0.tgz
k -n "$NS" exec client -- curl -fsS "http://$GOSHRAN/index.yaml" > /work/tmp/goshran-index.yaml
cmp /work/tmp/artifact-index.yaml /work/tmp/goshran-index.yaml
echo 'PASS: actual containerd and Helm followed the two lab redirect hops; the index is byte-identical'
k -n "$NS" apply -f - <<YAML
apiVersion: rknetes.su/v1alpha1
kind: SociallySignificantResource
metadata: {name: goshran}
spec:
  serviceName: goshran
  selector: {app: goshran, 'k8s:io.kubernetes.pod.namespace': $SERVERS}
  approved: true
---
apiVersion: rknetes.su/v1alpha1
kind: WhitelistMode
metadata: {name: domestic-only}
spec: {enabled: true}
YAML
k -n "$NS" wait --for=condition=Active whitelistmode/domestic-only --timeout=60s
reader
wait_until k -n "$NS" exec client -- curl -fsS --max-time 3 "http://$GOSHRAN/v2/lab/shop/manifests/1"
if pull; then echo 'unexpected OCI pull through denied CDN' >&2; exit 1; fi
if chart; then echo 'unexpected chart pull through denied absolute URL' >&2; exit 1; fi
k -n "$NS" delete whitelistmode domestic-only
wait_until k -n "$NS" exec client -- curl -fsS --max-time 3 "$CDN/healthz"
k -n "$NS" apply -f - <<YAML
apiVersion: rknetes.su/v1alpha1
kind: SovereignBytePolicy
metadata: {name: customs}
spec:
  selector: {app: artifact-client}
  foreignCIDRs: ['$(k -n "$SERVERS" get pod cdn -o jsonpath='{.status.podIP}')/32']
  limit: 16384
YAML
reader
sleep 4
k -n "$NS" exec client -- curl -fsS --max-time 3 "$CDN/healthz"
if pull; then echo 'unexpected complete layer above 16 KiB' >&2; exit 1; fi
if chart; then echo 'unexpected complete chart above 16 KiB' >&2; exit 1; fi
k -n "$SERVERS" get pod cdn -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
k -n "$NS" delete sovereignbytepolicy customs
reader
pull
chart
expected=$(python3 -c 'import json; print(json.load(open("/work/tmp/artifact-fixture/subjects.json"))["chartSHA256"])')
k -n "$NS" exec client -- sh -ec "echo '$expected  /tmp/shop-0.1.0.tgz' | sha256sum -c -"
k -n "$SERVERS" logs registry --tail=40
k -n "$SERVERS" logs cdn --tail=40
echo 'PASS: whitelist and actual per-flow byte policy blocked real OCI/Helm clients while small health probes remained green; removal restored full verified artifacts'
