#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
prefix=${RK_STAND_PREFIX:-rk}
memory=${RK_NODE_MEMORY:-8Gi}
[[ "$prefix" == rk || "$prefix" == rk-clean ]] || exit 2
[[ "$memory" == 8Gi || "$memory" == 5Gi || "$memory" == 3Gi ]] || exit 2
if [[ "${1:-create}" == boot-installed ]]; then
  for name in "$prefix-cp" "$prefix-worker1" "$prefix-worker2"; do
    wk patch vminstance.apps.cozystack.io "$name" --type merge -p "{\"spec\":{\"disks\":[{\"name\":\"$name-system\"},{\"name\":\"$name-media\"}]}}"
    previous=$(wk get "vmi/vm-instance-$name" -o jsonpath='{.metadata.uid}')
    virtctl --kubeconfig "$KUBECONFIG" --context admin@workshop -n "$RK_NS" restart "vm-instance-$name"
    restarted=false
    for _ in $(seq 1 150); do
      current=$(wk get "vmi/vm-instance-$name" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)
      if [[ -n "$current" && "$current" != "$previous" ]] && wk wait --for=condition=Ready "vmi/vm-instance-$name" --timeout=5s; then restarted=true; break; fi
      sleep 2
    done
    [[ "$restarted" == true ]] || { echo "$name did not restart" >&2; exit 1; }
  done
  exit 0
fi
for name in "$prefix-cp" "$prefix-worker1" "$prefix-worker2"; do
  sed "s/NODE/$name/g; s/memory: 8Gi/memory: $memory/" "$RK_ROOT/hack/workshop/node.yaml" | wk apply -f -
done
