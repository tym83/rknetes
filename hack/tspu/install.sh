#!/usr/bin/env bash
# Install only inside the marked nested stand; artifacts are hash-verified.
set -euo pipefail
source "$(dirname "$0")/../e2e/common.sh"
export TSPU_URL=${TSPU_URL:-http://10.244.8.11:8080/optional}
export TSPU_SHA=$(sha256sum /work/out/optional/tspu | cut -d' ' -f1)
export TSPU_OBJECT_SHA=$(sha256sum /work/out/optional/tspu.o | cut -d' ' -f1)
export TSPU_IMAGE=$(k -n rknet-system get deployment rknet-controller -o jsonpath='{.spec.template.spec.containers[0].image}')
k label namespace rknet-system pod-security.kubernetes.io/enforce=privileged --overwrite
python3 /work/src/rknetes/hack/tspu/render.py | k apply -f -
k -n rknet-system rollout status daemonset/tspu --timeout=180s
