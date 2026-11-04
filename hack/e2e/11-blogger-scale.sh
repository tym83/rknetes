#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-watch-scale
new_namespace "$NS"
original=$(k -n rknet-system get deployment watch-office -o jsonpath='{.spec.template.spec.containers[0].resources}')
forward=
restore() {
  stop_forward
  patch=$(python3 -c 'import json,sys;print(json.dumps([{"op":"replace","path":"/spec/template/spec/containers/0/resources","value":json.loads(sys.argv[1])}]))' "$original")
  k -n rknet-system patch deployment watch-office --type json -p "$patch"
  k -n rknet-system rollout status deployment/watch-office --timeout=120s
}
trap restore EXIT
k -n rknet-system patch deployment watch-office --type json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits","value":{"cpu":"2","memory":"2Gi"}}]'
k -n rknet-system rollout status deployment/watch-office --timeout=120s
start_forward rknet-system service/watch-office 19447:443
/work/out/optional/watch-audience --kubeconfig "$KUBECONFIG" --namespace "$NS" --server https://127.0.0.1:19447 --ca "$RK_TLS_DIR/watch/tls.crt"
k -n "$NS" get bloggerregistration kube-root-ca.crt -o json | python3 -c 'import json,sys;r=json.load(sys.stdin);assert r["spec"]["threshold"]==10000;assert r["status"]["observedConcurrentWatches"]==10001;assert r["spec"]["registered"];print(json.dumps(r["status"],indent=2))'
