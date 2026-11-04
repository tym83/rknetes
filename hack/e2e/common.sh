#!/usr/bin/env bash
set -euo pipefail
export PATH=/work/bin:/work/out/rknetes:$PATH
export KUBECONFIG=${RKNETES_KUBECONFIG:-/work/kube/rknetes.conf}
case "$KUBECONFIG" in
  /work/kube/rknetes.conf|/work/cleanroom/kube/rknetes.conf) ;;
  *) echo 'tests require a dedicated nested kubeconfig' >&2; exit 1 ;;
esac
export RK_TLS_DIR=${RK_TLS_DIR:-/work/tls}
case "$RK_TLS_DIR" in /work/tls|/work/cleanroom/tls) ;; *) exit 2 ;; esac
k() { kubectl --context admin@workshop "$@"; }
start_lab_controller() {
  k label namespace "$NS" rknetes.su/independent-controller=true --overwrite
  /work/out/optional/rknet-controller --kubeconfig "$KUBECONFIG" --context admin@workshop --namespace "$NS" > "/work/tmp/controller-$NS.log" 2>&1 &
  lab_controller=$!
}
stop_lab_controller() {
  if [[ -n "${lab_controller:-}" ]]; then kill "$lab_controller" 2>/dev/null || true; wait "$lab_controller" 2>/dev/null || true; fi
}
start_forward() {
  local namespace=$1 resource=$2 ports=$3
  forward_log=$(mktemp /work/tmp/rknetes-forward.XXXXXX)
  kubectl --context admin@workshop -n "$namespace" port-forward "$resource" "$ports" > "$forward_log" 2>&1 &
  forward=$!
  for _ in $(seq 1 20); do
    if ! kill -0 "$forward" 2>/dev/null; then cat "$forward_log" >&2; stop_forward; return 1; fi
    if grep -q 'Forwarding from' "$forward_log"; then return 0; fi
    sleep 1
  done
  cat "$forward_log" >&2
  stop_forward
  return 1
}
stop_forward() {
  if [[ -n "${forward:-}" ]]; then kill "$forward" 2>/dev/null || true; wait "$forward" 2>/dev/null || true; fi
  if [[ -n "${forward_log:-}" ]]; then rm -f "$forward_log"; fi
}
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
