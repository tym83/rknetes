#!/usr/bin/env bash
# Run after 08-artifact-chain; all three real kubelets use the lab Goshran hop.
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-artifact-services
[[ "$(k get namespace "$NS" -o jsonpath='{.metadata.labels.rknetes\.su/lab}')" == true ]]
IMAGE=$(cat /work/out/tools/lab-image.ref)
REGISTRY=http://$(k -n "$NS" get pod registry -o jsonpath='{.status.podIP}'):8080
SHA=$(sha256sum /work/out/optional/goshran | cut -d' ' -f1)
OLD_SECURITY=$(k get namespace "$NS" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}')
cleanup() {
 k -n "$NS" delete daemonset goshran-node-pull --ignore-not-found --wait=true
 if [[ -n "$OLD_SECURITY" ]]; then k label namespace "$NS" pod-security.kubernetes.io/enforce="$OLD_SECURITY" --overwrite; else k label namespace "$NS" pod-security.kubernetes.io/enforce-; fi
}
trap cleanup EXIT
k label namespace "$NS" pod-security.kubernetes.io/enforce=privileged --overwrite
k -n "$NS" apply -f - <<YAML
apiVersion: apps/v1
kind: DaemonSet
metadata: {name: goshran-node-pull}
spec:
  selector: {matchLabels: {app: goshran-node-pull}}
  template:
    metadata: {labels: {app: goshran-node-pull}}
    spec:
      automountServiceAccountToken: false
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      tolerations: [{operator: Exists}]
      initContainers:
      - name: binary
        image: $IMAGE
        command: [sh, -ec, "curl -fsS http://10.244.8.11:8080/optional/goshran -o /rk/goshran; echo '$SHA  /rk/goshran' | sha256sum -c -; chmod +x /rk/goshran"]
        volumeMounts: [{name: bin, mountPath: /rk}]
      containers:
      - name: goshran
        image: $IMAGE
        command: [/rk/goshran, --listen, '127.0.0.1:5007', --upstream, '$REGISTRY', --index, /index/index.yaml]
        readinessProbe: {exec: {command: [curl, -fsS, 'http://127.0.0.1:5007/healthz']}, periodSeconds: 1}
        volumeMounts: [{name: bin, mountPath: /rk}, {name: index, mountPath: /index}]
      volumes: [{name: bin, emptyDir: {}}, {name: index, configMap: {name: upstream-index}}]
YAML
k -n "$NS" rollout status daemonset/goshran-node-pull --timeout=180s
for node in $(k get nodes -o jsonpath='{.items[*].metadata.name}'); do
 k -n "$NS" run "pull-$node" --image=127.0.0.1:5007/lab/shop:1 --image-pull-policy=Always \
  --overrides="{\"spec\":{\"nodeName\":\"$node\",\"tolerations\":[{\"operator\":\"Exists\"}]}}"
done
k -n "$NS" wait --for=condition=Ready pods -l run --timeout=180s
for node in $(k get nodes -o jsonpath='{.items[*].metadata.name}'); do
 k -n "$NS" exec "pull-$node" -- /bin/busybox echo image-executed-on-native-kubelet
done
sleep 3
k -n "$NS" get pods -o json > /work/tmp/goshran-native-pulls.json
python3 - <<'PY'
import json
subjects=json.load(open('/work/tmp/artifact-fixture/subjects.json'))
pods=[p for p in json.load(open('/work/tmp/goshran-native-pulls.json'))['items'] if p['metadata']['name'].startswith('pull-')]
assert len(pods)==3,len(pods)
assert len({p['spec']['nodeName'] for p in pods})==3
for p in pods:
 assert p['spec']['containers'][0]['image']=='127.0.0.1:5007/lab/shop:1'
 status=p['status']['containerStatuses'][0];assert status['ready'] and status['restartCount']==0;assert 'running' in status['state']
 actual=status['imageID']
 assert actual.endswith(subjects['manifestDigest']),(p['metadata']['name'],actual)
 print('PASS native kubelet pull:',p['spec']['nodeName'],actual)
PY
k -n "$NS" get events --field-selector reason=Pulled -o wide
echo 'PASS: the entire three-node lab pull profile used Goshran and ran the actual image after redirected blob downloads'
