#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-whitelist-capacity
new_namespace "$NS"
k label namespace "$NS" pod-security.kubernetes.io/enforce=privileged
fixture bank
fixture gosuslugi
fixture detsky-mir
client
NODE=$(k -n "$NS" get pod client -o jsonpath='{.spec.nodeName}')
ENDPOINT=$(k -n "$NS" get ciliumendpoint client -o jsonpath='{.status.id}')
CILIUM=$(k -n kube-system get pods -l k8s-app=cilium --field-selector="spec.nodeName=$NODE" -o jsonpath='{.items[0].metadata.name}')
SHA=$(sha256sum /work/out/optional/policy-map-probe | cut -d' ' -f1)
k -n "$NS" apply -f - <<YAML
apiVersion: v1
kind: ServiceAccount
metadata: {name: capacity-probe}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: {name: rknet-capacity-probe}
rules:
- apiGroups: ['']
  resources: [namespaces, configmaps]
  verbs: [get]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: {name: rknet-capacity-probe}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: rknet-capacity-probe}
subjects: [{kind: ServiceAccount, name: capacity-probe, namespace: $NS}]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: capacity-probe}
rules:
- apiGroups: ['']
  resources: [pods]
  verbs: [get]
- apiGroups: [cilium.io]
  resources: [ciliumendpoints]
  verbs: [get]
- apiGroups: ['']
  resources: [configmaps]
  verbs: [get, create, update]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: capacity-probe}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: Role, name: capacity-probe}
subjects: [{kind: ServiceAccount, name: capacity-probe}]
---
apiVersion: v1
kind: Pod
metadata: {name: capacity-probe}
spec:
  nodeName: $NODE
  serviceAccountName: capacity-probe
  restartPolicy: Never
  initContainers:
  - name: binary
    image: busybox:1.37
    command: [sh, -ec, "wget -q -O /rk/probe http://10.244.8.11:8080/optional/policy-map-probe; echo '$SHA  /rk/probe' | sha256sum -c -; chmod +x /rk/probe"]
    volumeMounts: [{name: bin, mountPath: /rk}]
  containers:
  - name: probe
    image: busybox:1.37
    command: [/rk/probe, --namespace, $NS, --pod, client, --node, $NODE, --hold, 30s]
    securityContext: {privileged: true}
    volumeMounts: [{name: bin, mountPath: /rk}, {name: bpf, mountPath: /sys/fs/bpf}]
  volumes:
  - {name: bin, emptyDir: {}}
  - name: bpf
    hostPath: {path: /sys/fs/bpf, type: Directory}
YAML
full() { k -n "$NS" logs capacity-probe -c probe | grep MAP_FULL; }
wait_until full
if k -n kube-system exec "$CILIUM" -- cilium-dbg bpf policy add "$ENDPOINT" egress 2131000000 4445/tcp > /work/tmp/cilium-overflow.txt 2>&1; then
 echo 'Cilium unexpectedly inserted into the full map' >&2; exit 1
fi
cat /work/tmp/cilium-overflow.txt
grep -Ei 'no space|too (many|large)|map.*full|argument list too long' /work/tmp/cilium-overflow.txt
k -n "$NS" wait --for=jsonpath='{.status.phase}'=Succeeded pod/capacity-probe --timeout=90s
k -n "$NS" logs capacity-probe -c probe
MAX=$(k -n "$NS" get configmap policy-map-measurement -o jsonpath='{.data.maxEntries}')
start_lab_controller
trap 'stop_lab_controller; k delete clusterrolebinding/rknet-capacity-probe clusterrole/rknet-capacity-probe --ignore-not-found' EXIT
for name in bank gosuslugi; do
 k -n "$NS" apply -f - <<YAML
apiVersion: rknetes.su/v1alpha1
kind: SociallySignificantResource
metadata: {name: $name}
spec: {serviceName: $name, selector: {app: $name}, approved: true}
YAML
 sleep 1
done
k -n "$NS" apply -f - <<YAML
apiVersion: rknetes.su/v1alpha1
kind: WhitelistMode
metadata: {name: mobile}
spec: {enabled: true, capacityMeasurement: policy-map-measurement, reservedEntries: $((MAX-2))}
YAML
BANK=$(k -n "$NS" get pod bank -o jsonpath='{.status.podIP}')
STORE=$(k -n "$NS" get pod detsky-mir -o jsonpath='{.status.podIP}')
k -n "$NS" wait --for=condition=Whitelisted socialresources/bank --timeout=60s
wait_until probe "http://$BANK:8080"
wait_until assert_blocked "http://$STORE:8080"
k -n "$NS" apply -f - <<'YAML'
apiVersion: rknetes.su/v1alpha1
kind: SociallySignificantResource
metadata: {name: detsky-mir}
spec: {serviceName: detsky-mir, selector: {app: detsky-mir}, approved: true}
YAML
k -n "$NS" wait --for=condition=Whitelisted=False socialresources/bank --timeout=60s
wait_until assert_blocked "http://$BANK:8080"
wait_until probe "http://$STORE:8080"
k -n "$NS" get whitelistmode mobile -o json
k -n "$NS" get socialresources -o json
echo 'PASS: kernel/Cilium overflow rejects insertion without eviction; the measured-capacity admission queue evicts the oldest bank approval'
