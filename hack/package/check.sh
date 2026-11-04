#!/usr/bin/env bash
set -euo pipefail
source /work/src/rknetes/hack/e2e/common.sh
k wait --for=condition=Ready repository.kubepkg.dev/rknetes --timeout=180s
k wait --for=condition=Ready package.kubepkg.dev/kuberoot-rknetes --timeout=300s
current_binaries() {
  k -n rknet-system get deployment/rknet-controller deployment/rknet-admission deployment/watch-office daemonset/maxlet -o json | python3 -c '
import hashlib,json,pathlib,sys
objects=json.load(sys.stdin)["items"]
for obj in objects:
    name=obj["metadata"]["name"]
    expected=hashlib.sha256((pathlib.Path("/work/out/rknetes")/name).read_bytes()).hexdigest()
    command=obj["spec"]["template"]["spec"]["initContainers"][0]["command"]
    if command[-1]!=expected: raise SystemExit(1)
'
}
wait_until current_binaries
for name in rknet-controller rknet-admission watch-office; do
  k -n rknet-system rollout status "deployment/$name" --timeout=180s
done
k -n rknet-system rollout status daemonset/maxlet --timeout=180s
k -n rknet-system get pods -l app=rknet-controller -o json | python3 -c '
import json,sys
pod=json.load(sys.stdin)["items"][0]
assert "@sha256:" in pod["spec"]["containers"][0]["image"]
assert "sha256sum -c" in " ".join(pod["spec"]["initContainers"][0]["command"])
print("PASS: signed package Ready; runtime image pinned; downloaded binary verified by SHA256")'
mkdir -p /work/evidence/package
k get repository.kubepkg.dev/rknetes package.kubepkg.dev/kuberoot-rknetes -o yaml > /work/evidence/package/installed.yaml
sha256sum /work/out/packages/index.yaml /work/out/packages/rknetes-0.1.0-3.tgz > /work/evidence/package/sha256.txt
