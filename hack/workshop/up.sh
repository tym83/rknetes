#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
export RK_STAND_PREFIX=${RK_STAND_PREFIX:-rk}
[[ "$RK_STAND_PREFIX" == rk || "$RK_STAND_PREFIX" == rk-clean ]] || exit 2
prefix=$RK_STAND_PREFIX
resume=false
if wk get vminstance.apps.cozystack.io "$prefix-cp" >/dev/null 2>&1; then
  if [[ "$prefix" == rk-clean && "${RK_RESUME_UNINSTALLED:-0}" == 1 && "${RK_REUSE_ARTIFACTS:-0}" == 1 ]]; then
    resume=true
  else
    echo 'The stand already exists. up.sh never reinstalls existing system disks.' >&2
    exit 1
  fi
fi
kubectl --context admin@workshop apply -f "$RK_ROOT/hack/workshop/tenant.yaml"
kubectl --context admin@workshop -n tenant-root wait --for=condition=Ready tenant/rknetes --timeout=180s
if ! wk get pod builder >/dev/null 2>&1; then wk apply -f "$RK_ROOT/hack/workshop/builder.yaml"; fi
wk wait --for=condition=Ready pod/builder --timeout=180s
if [[ "${RK_REUSE_ARTIFACTS:-0}" == 1 ]]; then
  [[ "${RK_ROOTFS_SHA256:-}" =~ ^[0-9a-f]{64}$ ]] || { echo 'reusing an image requires its recorded rootfs SHA256' >&2; exit 2; }
  printf '%s  /work/out/amd64/rootfs.squashfs\n' "$RK_ROOTFS_SHA256" | builder sha256sum -c -
  "$RK_ROOT/hack/dev/sync.sh"
else
  "$RK_ROOT/hack/dev/build.sh"
  builder bash /work/src/rknetes/hack/dev/tools.sh
  builder bash /work/src/rknetes/hack/dev/bpf.sh
  builder sh -c '[ -d /work/src/kubernetes-rknetes ] || git clone --quiet --depth 1 --branch v1.37.1 https://github.com/kubernetes/kubernetes /work/src/kubernetes-rknetes'
  builder bash /work/src/rknetes/hack/importozameshchenie.sh /work/src/kubernetes-rknetes
  builder bash /work/src/rknetes/hack/package/kine-source.sh
  builder bash /work/src/rknetes/hack/import/tools.sh
  builder bash /work/src/rknetes/hack/import/compiler.sh
  "$RK_ROOT/hack/kuberoot.sh" build amd64
  "$RK_ROOT/hack/kuberoot.sh" bundle amd64
  builder bash /work/src/rknetes/hack/package/sbom.sh
  builder bash /work/src/rknetes/hack/research/archive-tools.sh
  builder bash /work/src/rknetes/hack/research/lab-image.sh
fi
if [[ "$resume" != true ]]; then
  "$RK_ROOT/hack/kuberoot.sh" media amd64 kuberoot.datastore=etcd kuberoot.pod-network=none kuberoot.pod-cidr=10.42.0.0/16 kuberoot.service-cidr=10.96.0.0/12 kuberoot.nameserver=1.1.1.1,8.8.8.8
  "$RK_ROOT/hack/workshop/nodes.sh"
fi
for name in "$prefix-cp" "$prefix-worker1" "$prefix-worker2"; do
  for _ in $(seq 1 90); do
    wk get "vmi/vm-instance-$name" >/dev/null 2>&1 && break
    sleep 2
  done
  wk wait --for=condition=Ready "vmi/vm-instance-$name" --timeout=300s
done
addresses() {
  cp_ip=$(wk get vmi "vm-instance-$prefix-cp" -o jsonpath='{.status.interfaces[0].ipAddress}')
  w1_ip=$(wk get vmi "vm-instance-$prefix-worker1" -o jsonpath='{.status.interfaces[0].ipAddress}')
  w2_ip=$(wk get vmi "vm-instance-$prefix-worker2" -o jsonpath='{.status.interfaces[0].ipAddress}')
}
if [[ "$prefix" == rk-clean ]]; then
  remote=(env RKNETES_KUBECONFIG=/work/cleanroom/kube/rknetes.conf RK_TLS_DIR=/work/cleanroom/tls RK_PACKAGE_EVIDENCE=/work/evidence/cleanroom-package)
else
  remote=(env RKNETES_KUBECONFIG=/work/kube/rknetes.conf)
fi
addresses
builder "${remote[@]}" bash /work/src/rknetes/hack/stand/bootstrap.sh install "$cp_ip" "$w1_ip" "$w2_ip"
"$RK_ROOT/hack/workshop/nodes.sh" boot-installed
addresses
builder "${remote[@]}" bash /work/src/rknetes/hack/stand/bootstrap.sh configure "$cp_ip" "$w1_ip" "$w2_ip"
files_ip=$(wk get pod builder -o jsonpath='{.status.podIP}')
builder "${remote[@]}" RK_BINARY_URL="http://$files_ip:8080/rknetes" bash /work/src/rknetes/hack/stand/install.sh
builder "${remote[@]}" bash /work/src/rknetes/hack/research/preload-lab-image.sh
if [[ "${RK_REUSE_ARTIFACTS:-0}" != 1 ]]; then builder "${remote[@]}" bash /work/src/rknetes/hack/package/build.sh "$files_ip"; fi
builder "${remote[@]}" bash /work/src/rknetes/hack/package/install.sh "$files_ip"
