#!/usr/bin/env bash
set -euo pipefail
source /work/src/rknetes/hack/e2e/common.sh
NS=${RK_SHOP_NAMESPACE:?}
SERVERS=${RK_SHOP_SERVERS:?}
SHOP_IP=${RK_SHOP_IP:?}
trap stop_forward EXIT
echo 'Scene8: why observes the same shop and the registry/whitelist history.'
/work/out/optional/rknetesctl --kubeconfig "$KUBECONFIG" --context admin@workshop -n "$NS" why shop
start_forward kube-system service/hubble-relay 14245:80
/work/out/optional/rknetesctl --kubeconfig "$KUBECONFIG" --context admin@workshop --hubble 127.0.0.1:14245 -n "$NS" why shop
stop_forward
for ns in "$NS" "$SERVERS"; do
 k -n "$ns" apply -f - <<'YAML'
apiVersion: rknetes.su/v1alpha1
kind: CallRestriction
metadata: {name: calls}
spec: {enabled: true}
YAML
done
if k -n "$SERVERS" exec recovery -- echo unauthorized-call; then exit 1; fi
echo 'Scene9: a real MAX call performs the narrowly authorized out-of-band repair.'
repair(){ hodatay --context admin@workshop --tls-server-name="$RK_MAX_TLS_SERVER_NAME" -n "$SERVERS" max exec recovery -- /rk/kubectl --context admin@workshop --kubeconfig /config/config -n "$NS" "$@"; }
repair delete reestrentry telegram rutracker
repair delete ciliumnetworkpolicy reestr-telegram reestr-rutracker --ignore-not-found
repair patch pod rutracker --type merge -p '{"metadata":{"finalizers":[]}}'
wait_until hodatay --context admin@workshop --tls-server-name="$RK_MAX_TLS_SERVER_NAME" -n "$NS" max exec buyer -- curl -fsS --max-time 3 "http://$SHOP_IP:8080"
[[ -z "$(k -n "$NS" get pod rutracker --ignore-not-found -o name)" ]]
echo 'PASS: MAX performed actual policy deletion and finalizer removal; this shop serves orders again'
