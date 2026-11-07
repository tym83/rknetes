#!/usr/bin/env bash
# Run only against the dedicated nested kubeconfig after its marker is present.
set -euo pipefail
source /work/src/rknetes/hack/e2e/common.sh
CP_IP=${1:?nested control-plane address}
/work/bin/helm upgrade --install cilium cilium --repo https://helm.cilium.io --version 1.20.4 --namespace kube-system \
  --kube-context admin@workshop --set ipam.mode=kubernetes --set kubeProxyReplacement=false \
  --set cni.chainingMode=portmap --set rollOutCiliumPods=true \
  --set bandwidthManager.enabled=true --set 'policyCIDRMatchMode={pods,nodes}' \
  --set k8sServiceHost="$CP_IP" --set k8sServicePort=6443 --set operator.replicas=1 \
  --set bpf.masquerade=true --set hubble.enabled=true --set hubble.relay.enabled=true
k -n kube-system rollout status daemonset/cilium --timeout=300s
