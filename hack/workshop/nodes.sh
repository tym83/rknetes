#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
if [[ "${1:-create}" == boot-installed ]]; then
  for name in rk-cp rk-worker1 rk-worker2; do
    wk patch vminstance.apps.cozystack.io "$name" --type merge -p "{\"spec\":{\"disks\":[{\"name\":\"$name-system\"},{\"name\":\"$name-media\"}]}}"
    virtctl --kubeconfig "$KUBECONFIG" --context admin@workshop -n "$RK_NS" restart "vm-instance-$name"
  done
  exit 0
fi
for name in rk-cp rk-worker1 rk-worker2; do
  sed "s/NODE/$name/g" "$RK_ROOT/hack/workshop/node.yaml" | wk apply -f -
done
