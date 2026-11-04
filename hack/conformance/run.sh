#!/usr/bin/env bash
# Run inside the tenant builder after disruptive lab tests have finished.
set -euo pipefail
source "$(dirname "$0")/../e2e/common.sh"
RUN=${1:?unique run name required}
FOCUS=${2:-}
[[ "$RUN" =~ ^[a-zA-Z0-9._-]+$ ]] || exit 2
DIR=/work/evidence/conformance-$RUN
IMAGE=registry.k8s.io/conformance:v1.37.1@sha256:c48b0c496e600718f50fa0cc19a49f3c4e27cc83894da84ccccc539539884c3b
[[ ! -e "$DIR" ]] || { echo 'evidence directory already exists' >&2; exit 1; }
mkdir -p "$DIR"
k version -o yaml > "$DIR/version.yaml"
k get nodes -o wide > "$DIR/nodes.txt"
k get namespace -L rknetes.su/lab > "$DIR/namespaces.txt"
k -n rknet-system get deployments,daemonsets -o wide > "$DIR/addons.txt"
k -n kube-system get cm cilium-config -o yaml > "$DIR/cilium-config.yaml"
bash "$(dirname "$0")/build-runner.sh"
selection=(--conformance)
if [[ -n "$FOCUS" ]]; then selection=(--focus "$FOCUS"); fi
printf '%s\n' "${FOCUS:-all upstream Conformance specs}" > "$DIR/selection.txt"
printf '%s\n' "$IMAGE" > "$DIR/runner-image.txt"
set +e
# Hydrophone v0.5.0 prefers InClusterConfig even when --kubeconfig is supplied.
# Remove discovery env so the outer builder ServiceAccount is never selected.
env -u KUBERNETES_SERVICE_HOST -u KUBERNETES_SERVICE_PORT hydrophone-rknetes --kubeconfig "$KUBECONFIG" "${selection[@]}" --parallel 8 \
  --conformance-image "$IMAGE" \
  --namespace rknet-conformance --output-dir "$DIR" 2>&1 | tee "$DIR/driver.log"
code=${PIPESTATUS[0]}
set -e
printf '%s\n' "$code" > "$DIR/exit-code"
python3 "$(dirname "$0")/report.py" "$DIR" || true
exit "$code"
