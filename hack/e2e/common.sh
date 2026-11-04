#!/usr/bin/env bash
set -euo pipefail
export PATH=/work/bin:/work/out/rknetes:$PATH
export KUBECONFIG=${RKNETES_KUBECONFIG:-/work/kube/rknetes.conf}
[[ "$KUBECONFIG" == /work/kube/rknetes.conf ]] || { echo 'tests require the dedicated nested kubeconfig' >&2; exit 1; }
k() { kubectl --context admin@workshop "$@"; }
[[ "$(k -n kube-system get cm rknetes-stand -o jsonpath='{.data.scope}')" == nested-only ]]
new_namespace() {
  local name=$1
  if k get ns "$name" >/dev/null 2>&1; then echo "namespace $name already exists; retain evidence or remove it explicitly" >&2; exit 1; fi
  k create ns "$name"
  k label ns "$name" rknetes.su/lab=true
}
wait_until() {
  local deadline=$((SECONDS+120))
  until "$@"; do [[ $SECONDS -lt $deadline ]] || return 1; sleep 2; done
}
probe() { k -n "$NS" exec client -- wget -q -T 3 -O - "$1"; }
assert_blocked() { if probe "$1"; then echo "unexpectedly reachable: $1" >&2; return 1; fi; }
fixture() {
  k -n "$NS" run "$1" --image=busybox:1.37 --labels="app=$1" --command -- sh -c 'mkdir -p /tmp/www; echo ok > /tmp/www/index.html; httpd -f -p 8080 -h /tmp/www'
  k -n "$NS" wait --for=condition=Ready "pod/$1" --timeout=120s
}
client() {
  k -n "$NS" run client --image=busybox:1.37 --command -- sleep 3600
  k -n "$NS" wait --for=condition=Ready pod/client --timeout=120s
}
