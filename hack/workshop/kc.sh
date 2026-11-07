#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
builder /work/bin/kubectl --kubeconfig /work/kube/rknetes.conf --context admin@workshop "$@"
