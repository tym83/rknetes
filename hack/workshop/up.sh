#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
if wk get vminstance.apps.cozystack.io rk-cp >/dev/null 2>&1; then
  echo 'The stand already exists. Use kc.sh to inspect it; up.sh never reinstalls existing disks.' >&2
  exit 1
fi
kubectl --context admin@workshop apply -f "$RK_ROOT/hack/workshop/tenant.yaml"
kubectl --context admin@workshop -n tenant-root wait --for=condition=Ready tenant/rknetes --timeout=180s
wk apply -f "$RK_ROOT/hack/workshop/builder.yaml"
wk wait --for=condition=Ready pod/builder --timeout=180s
"$RK_ROOT/hack/dev/build.sh"
builder bash /work/src/rknetes/hack/dev/tools.sh
builder bash /work/src/rknetes/hack/dev/bpf.sh
builder sh -c '[ -d /work/src/kubernetes-rknetes ] || git clone --quiet --depth 1 --branch v1.37.1 https://github.com/kubernetes/kubernetes /work/src/kubernetes-rknetes'
builder bash /work/src/rknetes/hack/importozameshchenie.sh /work/src/kubernetes-rknetes
"$RK_ROOT/hack/kuberoot.sh" build amd64
"$RK_ROOT/hack/kuberoot.sh" media amd64 kuberoot.datastore=etcd kuberoot.pod-network=none kuberoot.pod-cidr=10.42.0.0/16 kuberoot.service-cidr=10.96.0.0/12 kuberoot.nameserver=1.1.1.1,8.8.8.8
"$RK_ROOT/hack/workshop/nodes.sh"
for name in rk-cp rk-worker1 rk-worker2; do
  for _ in $(seq 1 90); do
    wk get "vmi/vm-instance-$name" >/dev/null 2>&1 && break
    sleep 2
  done
  wk wait --for=condition=Ready "vmi/vm-instance-$name" --timeout=300s
done
cp_ip=$(wk get vmi vm-instance-rk-cp -o jsonpath='{.status.interfaces[0].ipAddress}')
w1_ip=$(wk get vmi vm-instance-rk-worker1 -o jsonpath='{.status.interfaces[0].ipAddress}')
w2_ip=$(wk get vmi vm-instance-rk-worker2 -o jsonpath='{.status.interfaces[0].ipAddress}')
builder bash /work/src/rknetes/hack/stand/bootstrap.sh install "$cp_ip" "$w1_ip" "$w2_ip"
"$RK_ROOT/hack/workshop/nodes.sh" boot-installed
builder bash /work/src/rknetes/hack/stand/bootstrap.sh configure "$cp_ip" "$w1_ip" "$w2_ip"
files_ip=$(wk get pod builder -o jsonpath='{.status.podIP}')
builder env RK_BINARY_URL="http://$files_ip:8080/rknetes" bash /work/src/rknetes/hack/stand/install.sh
