#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-measurement-office
new_namespace "$NS"
start_lab_controller
cleanup() {
 stop_lab_controller
 k delete clusterrolebinding "$NS" --ignore-not-found
 k delete clusterrole "$NS" --ignore-not-found
}
trap cleanup EXIT
MS=registry.k8s.io/metrics-server/metrics-server:v0.8.0
BB=quay.io/prometheus/blackbox-exporter:v0.27.0
MS="$MS@$(/work/bin/crane digest --platform linux/amd64 "$MS")"
BB="$BB@$(/work/bin/crane digest --platform linux/amd64 "$BB")"
k -n "$NS" create serviceaccount measurement
k create clusterrole "$NS" --verb=get,list,watch --resource=nodes,pods,nodes/metrics
k create clusterrolebinding "$NS" --clusterrole="$NS" --serviceaccount="$NS:measurement"
k -n "$NS" run metrics-server --image="$MS" --labels=rknetes.su/measurement=speedtest \
 --overrides='{"spec":{"serviceAccountName":"measurement"}}' -- \
 --secure-port=4443 --cert-dir=/tmp --kubelet-insecure-tls --authentication-skip-lookup --metric-resolution=15s
k -n "$NS" run blackbox --image="$BB" --labels=rknetes.su/measurement=blackbox
fixture dashboard
k -n "$NS" label pod dashboard rknetes.su/measurement=vpn-dashboard
k -n "$NS" run client --image="$(cat /work/out/tools/lab-image.ref)" --command -- sleep 3600
k -n "$NS" wait --for=condition=Ready pod/client pod/metrics-server pod/blackbox --timeout=180s
MSIP=$(k -n "$NS" get pod metrics-server -o jsonpath='{.status.podIP}')
BBIP=$(k -n "$NS" get pod blackbox -o jsonpath='{.status.podIP}')
DASH=$(k -n "$NS" get pod dashboard -o jsonpath='{.status.podIP}')
CREATED=$(k -n "$NS" get pod dashboard -o jsonpath='{.metadata.creationTimestamp}')
get() { k -n "$NS" exec client -- curl -kfsS --max-time 3 "$1"; }
wait_until get "https://$MSIP:4443/livez"
get "http://$BBIP:9115/probe?target=http://$DASH:8080&module=http_2xx" | grep '^probe_success 1'
get "http://$DASH:8080"
k -n "$NS" create configmap measurement-office --from-literal=enabled=true
blocked() { ! get "$1"; }
wait_until blocked "https://$MSIP:4443/livez"
wait_until blocked "http://$BBIP:9115/metrics"
[[ "$(/work/out/optional/hodatay --context admin@workshop top pods -n "$NS")" == 'Скорость в норме' ]]
echo "Real dashboard creation time: $CREATED; waiting for the default 900-second threshold"
while true; do
 age=$(python3 - "$CREATED" <<'PY'
import datetime,sys
print(int((datetime.datetime.now(datetime.timezone.utc)-datetime.datetime.fromisoformat(sys.argv[1].replace('Z','+00:00'))).total_seconds()))
PY
 )
 [[ "$age" -lt 890 ]] || break
 get "http://$DASH:8080" >/dev/null
 sleep 10
done
wait_until blocked "http://$DASH:8080"
k -n "$NS" get reestrentries -o json
k -n "$NS" get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].imageID}{"\n"}{end}'
k -n "$NS" patch configmap measurement-office --type merge -p '{"data":{"enabled":"false"}}'
wait_until get "https://$MSIP:4443/livez"
wait_until get "http://$BBIP:9115/metrics"
wait_until get "http://$DASH:8080"
echo 'PASS: real metrics-server and blackbox clients denied, dashboard enters registry after 15 actual minutes, explicit policy disable restores traffic'
