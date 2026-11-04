#!/usr/bin/env bash
# Run in the builder. Upgrade only the three guest node APIs given explicitly.
set -euo pipefail
export PATH=/work/bin:$PATH
URL=${1:?signed bundle URL}; SHA=${2:?SHA256}; shift 2
[[ $# == 3 && "$URL" == http://10.244.* ]] || { echo 'requires three nested guest addresses and a private workshop URL' >&2; exit 2; }
node() { local ip=$1; shift; kubectl --context admin@workshop --kubeconfig /work/kube/node.conf --server "https://$ip:50000" --request-timeout=10s "$@"; }
for ip in "$@"; do
  name=$(node "$ip" get osconfig -o jsonpath='{.items[0].metadata.name}')
  old=$(node "$ip" get bootentries -o jsonpath='{.items[?(@.status.booted==true)].metadata.name}')
  node "$ip" create -f - <<YAML
apiVersion: node.kuberoot.dev/v1alpha1
kind: Upgrade
metadata: {name: native-rknetes}
spec: {url: '$URL', sha256: '$SHA', reboot: true}
YAML
  rebooted=false
  for _ in $(seq 1 120); do
    current=$(node "$ip" get bootentries -o jsonpath='{.items[?(@.status.booted==true)].metadata.name}' 2>/dev/null || true)
    if [[ -n "$current" && "$current" != "$old" ]]; then rebooted=true; break; fi
    phase=$(node "$ip" get upgrade native-rknetes -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [[ "$phase" == Failed ]]; then node "$ip" get upgrade native-rknetes -o yaml; exit 1; fi
    sleep 3
  done
  [[ "$rebooted" == true ]] || { echo "$name did not boot the upgrade" >&2; exit 1; }
  node "$ip" get bootentries
  for _ in $(seq 1 60); do
    if kubectl --context admin@workshop --kubeconfig /work/kube/rknetes.conf wait --for=condition=Ready "node/$name" --timeout=5s; then break; fi
    sleep 3
  done
done
kubectl --context admin@workshop --kubeconfig /work/kube/rknetes.conf get nodes -o wide
kubectl --context admin@workshop --kubeconfig /work/kube/rknetes.conf get стручки -n rknet-system
