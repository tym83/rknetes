#!/usr/bin/env bash
# Run in the builder after the three nodes have booted. No credentials go to stdout.
set -euo pipefail
export PATH=/work/bin:$PATH
STAGE=${1:?install or configure stage}; shift
CP_IP=${1:?control plane VM IP}
W1_IP=${2:?worker 1 VM IP}
W2_IP=${3:?worker 2 VM IP}
mkdir -p /work/kube
cp /work/trust/admin.kubeconfig /work/kube/node.conf
kubectl --context admin@workshop --kubeconfig /work/kube/node.conf config rename-context kuberoot admin@workshop >/dev/null
node() { local address=$1; shift; kubectl --context admin@workshop --kubeconfig /work/kube/node.conf --server "https://$address:50000" --request-timeout=15s "$@"; }
if [[ "$STAGE" == install ]]; then
  for address in "$CP_IP" "$W1_IP" "$W2_IP"; do
    node "$address" get disks -o json > /work/tmp/disks.json
    python3 -c 'import json; ds=json.load(open("/work/tmp/disks.json"))["items"]; d=next(x for x in ds if x["metadata"]["name"]=="vdb"); assert not d.get("status",{}).get("role"), "system disk is not empty"'
    name=$(node "$address" get osconfig -o jsonpath='{.items[0].metadata.name}')
    node "$address" patch osconfig "$name" --type merge -p '{"spec":{"nameservers":["1.1.1.1","8.8.8.8"]}}'
    node "$address" create -f - <<'YAML'
apiVersion: node.kuberoot.dev/v1alpha1
kind: Installation
metadata: {name: system}
spec: {disk: vdb, reboot: false}
YAML
  done
  for address in "$CP_IP" "$W1_IP" "$W2_IP"; do
    ready=false
    for _ in $(seq 1 90); do
      phase=$(node "$address" get installation system -o jsonpath='{.status.phase}')
      if [[ "$phase" == Completed ]]; then ready=true; break; fi
      [[ "$phase" != Failed ]] || { node "$address" get installation system -o yaml; exit 1; }
      sleep 3
    done
    [[ "$ready" == true ]] || exit 1
  done
  echo 'Installations complete; boot the system disks before configure.'
  exit 0
fi
[[ "$STAGE" == configure ]] || exit 2
for address in "$CP_IP" "$W1_IP" "$W2_IP"; do
  ready=false
  for _ in $(seq 1 90); do
    if node "$address" get bootentries -o json > /work/tmp/install.json 2>/dev/null && python3 -c 'import json; a=json.load(open("/work/tmp/install.json")); exit(not any(x.get("status",{}).get("booted",False) for x in a["items"]))'; then ready=true; break; fi
    sleep 3
  done
  [[ "$ready" == true ]] || exit 1
done
node "$CP_IP" get kubeconfig admin -o jsonpath='{.kubeconfig}' > /work/kube/rknetes.conf
chmod 600 /work/kube/*.conf
old=$(kubectl --context admin@workshop --kubeconfig /work/kube/rknetes.conf config current-context)
if [[ "$old" != admin@workshop ]]; then kubectl --context admin@workshop --kubeconfig /work/kube/rknetes.conf config rename-context "$old" admin@workshop >/dev/null; fi
export KUBECONFIG=/work/kube/rknetes.conf
k() { kubectl --context admin@workshop "$@"; }
k -n kube-system create configmap rknetes-stand --from-literal=scope=nested-only --from-literal=podCIDR=10.42.0.0/16 --from-literal=serviceCIDR=10.96.0.0/12 --dry-run=client -o yaml | k apply -f -
for address in "$W1_IP" "$W2_IP"; do
  name=$(node "$address" get osconfigs -o jsonpath='{.items[0].metadata.name}')
  node "$CP_IP" create -f - <<YAML
apiVersion: node.kuberoot.dev/v1alpha1
kind: JoinTicket
metadata: {name: $name}
spec: {nodeName: $name, role: Worker}
YAML
  node "$CP_IP" get jointicket "$name" -o jsonpath='{.status.membership}' | node "$address" create -f -
done
helm upgrade --install cilium cilium --repo https://helm.cilium.io --version 1.20.4 --namespace kube-system \
  --kube-context admin@workshop --set ipam.mode=kubernetes --set kubeProxyReplacement=false \
  --set bandwidthManager.enabled=true --set 'policyCIDRMatchMode={pods,nodes}' \
  --set k8sServiceHost="$CP_IP" --set k8sServicePort=6443 --set operator.replicas=1 \
  --set bpf.masquerade=true --set hubble.enabled=true --set hubble.relay.enabled=true
k -n kube-system rollout status daemonset/cilium --timeout=300s
k wait --for=condition=Ready nodes --all --timeout=180s
k get nodes -o wide
