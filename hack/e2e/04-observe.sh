#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-whitelist
start_forward kube-system service/hubble-relay 14245:80
trap stop_forward EXIT
GOS=$(k -n "$NS" get service gosuslugi -o jsonpath='{.spec.clusterIP}')
assert_blocked "http://$GOS:8080"
observed_drop() {
  rknetesctl --kubeconfig "$KUBECONFIG" -n "$NS" --hubble 127.0.0.1:14245 why gosuslugi > /work/tmp/rknetes-observed-why.log
  grep 'lab-whitelist/client.*DROPPED' /work/tmp/rknetes-observed-why.log
}
wait_until observed_drop
cat /work/tmp/rknetes-observed-why.log
echo 'PASS: why reports actual Hubble dropped-packet verdicts alongside declared dependencies'
