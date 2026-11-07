#!/usr/bin/env bash
set -euo pipefail
source /work/src/rknetes/hack/e2e/common.sh
k wait --for=condition=Ready repository.kubepkg.dev/rknetes --timeout=180s
k wait --for=condition=Ready package.kubepkg.dev/kuberoot-rknetes --timeout=300s
current_binaries() {
  k -n rknet-system get deployment/rknet-controller deployment/rknet-admission deployment/watch-office daemonset/maxlet -o json | python3 -c '
import hashlib,json,pathlib,sys
objects=json.load(sys.stdin)["items"]
snapshot=pathlib.Path("/work/out/packages/binaries.sha256").read_text().strip()
for obj in objects:
    name=obj["metadata"]["name"]
    expected=hashlib.sha256((pathlib.Path("/work/out/rknetes")/name).read_bytes()).hexdigest()
    command=obj["spec"]["template"]["spec"]["initContainers"][0]["command"]
    if command[-1]!=expected or not command[-2].endswith("/releases/"+snapshot): raise SystemExit(1)
'
}
wait_until current_binaries
current_chart() {
  /work/bin/helm list --namespace rknet-system --kube-context admin@workshop -o json | python3 -c '
import json,sys
assert any(r["name"]=="rknetes" and r["chart"]=="rknetes-0.1.0-7" and r["status"]=="deployed" for r in json.load(sys.stdin))
'
}
wait_until current_chart
for name in rknet-controller rknet-admission watch-office; do
  k -n rknet-system rollout status "deployment/$name" --timeout=180s
done
k -n rknet-system rollout status daemonset/maxlet --timeout=180s
k -n rknet-system rollout status daemonset/tspu --timeout=180s
k -n rknet-system get daemonset tspu -o json | python3 -c '
import hashlib,json,pathlib,sys
p=json.load(sys.stdin)["spec"]["template"]
for name,field in [("tspu","binary"),("tspu.o","object")]:
 expected=hashlib.sha256((pathlib.Path("/work/out/rknetes")/name).read_bytes()).hexdigest()
 assert p["metadata"]["annotations"]["rknetes.su/"+field+"-sha256"]==expected
print("PASS: signed package includes the current TSPU binary and BPF object")'
k -n rknet-system get configmap runtime-artifacts -o json | python3 -c '
import hashlib,json,pathlib,sys
p=json.load(sys.stdin)["data"]
assert "@sha256:" in p["image"]
assert p["url"].endswith("/releases/"+pathlib.Path("/work/out/packages/binaries.sha256").read_text().strip())
for name in ["pigeon","drill-trigger","archive-agent"]:
 assert p["sha256."+name]==hashlib.sha256((pathlib.Path("/work/out/rknetes")/name).read_bytes()).hexdigest()
print("PASS: runtime helpers use the signed release hashes and immutable image")'

k -n rknet-system get pods -l app=rknet-controller -o json | python3 -c '
import json,sys
pod=json.load(sys.stdin)["items"][0]
assert "@sha256:" in pod["spec"]["containers"][0]["image"]
assert "sha256sum -c" in " ".join(pod["spec"]["initContainers"][0]["command"])
print("PASS: signed package Ready; runtime image pinned; downloaded binary verified by SHA256")'
evidence=${RK_PACKAGE_EVIDENCE:-/work/evidence/package}
[[ "$evidence" == /work/evidence/* ]] || exit 2
mkdir -p "$evidence"
k get repository.kubepkg.dev/rknetes package.kubepkg.dev/kuberoot-rknetes -o yaml > "$evidence/installed.yaml"
sha256sum /work/out/packages/index.yaml /work/out/packages/rknetes-0.1.0-7.tgz > "$evidence/sha256.txt"
