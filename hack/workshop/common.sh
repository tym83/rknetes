#!/usr/bin/env bash
set -euo pipefail
RK_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
export KUBECONFIG=${KUBECONFIG_WORKSHOP:-$HOME/workshop.txt}
RK_NS=tenant-rknetes
wk() { kubectl --context admin@workshop -n "$RK_NS" "$@"; }
builder() { wk exec -i builder -c tools -- "$@"; }
