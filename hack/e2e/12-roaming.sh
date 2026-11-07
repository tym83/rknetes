#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-roaming
new_namespace "$NS"
NODE=$(k get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[1].metadata.name}')
CP=$(k get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}')
OLD_LAB=$(k get node "$NODE" -o jsonpath='{.metadata.labels.rknetes\.su/lab}')
OLD_OWNER=$(k get node "$NODE" -o jsonpath='{.metadata.annotations.rknetes\.su/roaming-namespace}')
cleanup() {
 stop_lab_controller
 k taint node "$NODE" rknetes.su/returned-from-roaming- || true
 if [[ -n "$OLD_LAB" ]]; then k label node "$NODE" rknetes.su/lab="$OLD_LAB" --overwrite; else k label node "$NODE" rknetes.su/lab-; fi
 if [[ -n "$OLD_OWNER" ]]; then k annotate node "$NODE" rknetes.su/roaming-namespace="$OLD_OWNER" --overwrite; else k annotate node "$NODE" rknetes.su/roaming-namespace-; fi
}
trap cleanup EXIT
k label node "$NODE" rknetes.su/lab=true --overwrite
k annotate node "$NODE" "rknetes.su/roaming-namespace=$(k get namespace "$NS" -o jsonpath='{.metadata.uid}')" --overwrite
k -n "$NS" run captcha-cdn --image=busybox:1.37 --labels=app=captcha-cdn \
 --overrides="{\"spec\":{\"nodeName\":\"$CP\",\"tolerations\":[{\"operator\":\"Exists\"}]}}" --command -- sh -c 'mkdir /tmp/www; echo 2+2=4 >/tmp/www/index.html; httpd -f -p 8080 -h /tmp/www'
k -n "$NS" wait --for=condition=Ready pod/captcha-cdn --timeout=120s
CDN=$(k -n "$NS" get pod captcha-cdn -o jsonpath='{.status.podIP}')
HASH=$(printf '2+2=4\n' | sha256sum | cut -d' ' -f1)
k -n "$NS" create configmap roaming-office --from-literal=enabled=true --from-literal="captchaURL=http://$CDN:8080" --from-literal="captchaSHA256=$HASH"
block() {
 k -n "$NS" apply -f - <<'YAML'
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata: {name: foreign-captcha}
spec:
  endpointSelector: {matchLabels: {app: captcha-solver}}
  enableDefaultDeny: {ingress: false, egress: false}
  egressDeny: [{toEndpoints: [{matchLabels: {app: captcha-cdn}}]}]
YAML
}
start_lab_controller
history_ready() { [[ "$(k -n "$NS" get cm -l rknetes.su/managed=true -o name | grep -c 'roaming-')" == 1 ]]; }
wait_until history_ready
HISTORY=$(k -n "$NS" get cm -l rknetes.su/managed=true -o jsonpath='{.items[0].metadata.name}')
for scenario in silence migration; do
 block
 k -n "$NS" run "victim-$scenario" --image=busybox:1.37 --overrides="{\"spec\":{\"nodeName\":\"$NODE\"}}" --command -- sleep 3600
 k -n "$NS" wait --for=condition=Ready "pod/victim-$scenario" --timeout=120s
 stop_lab_controller
 if [[ "$scenario" == silence ]]; then
  OLD_TIME=$(date -u -d '73 hours ago' +%Y-%m-%dT%H:%M:%SZ)
  k -n "$NS" patch configmap "$HISTORY" --type merge -p "{\"data\":{\"lastSeen\":\"$OLD_TIME\"}}"
  EXPECTED=SilentFor72Hours
 else
  k -n "$NS" patch configmap "$HISTORY" --type merge -p '{"data":{"clusterUID":"controlled-previous-lab-cluster"}}'
  EXPECTED=ReturnedFromAnotherCluster
 fi
 start_lab_controller
 detected() { [[ "$(k -n "$NS" get coolingpolicies -o jsonpath='{.items[0].spec.reason}')" == "$EXPECTED" ]]; }
 wait_until detected
 POLICY=$(k -n "$NS" get coolingpolicies -o jsonpath='{.items[0].metadata.name}')
 k -n "$NS" wait --for=condition=Cooling "coolingpolicy/$POLICY" --timeout=120s
 k -n "$NS" wait --for=delete "pod/victim-$scenario" --timeout=90s
 SOLVER=$(k -n "$NS" get pod -l app=captcha-solver -o jsonpath='{.items[0].metadata.name}')
 blocked() { k -n "$NS" logs "$SOLVER" | grep -q 'Капча недоступна'; }
 wait_until blocked
 [[ "$(k -n "$NS" get coolingpolicy "$POLICY" -o jsonpath='{.spec.durationSeconds}')" == 86400 ]]
 [[ "$(k -n "$NS" get pod "$SOLVER" -o jsonpath='{.status.phase}')" == Running ]]
 k -n "$NS" logs "$SOLVER"
 k -n "$NS" delete ciliumnetworkpolicy foreign-captcha
 k -n "$NS" wait --for=jsonpath='{.status.phase}'=Succeeded "pod/$SOLVER" --timeout=120s
 k -n "$NS" wait --for=condition=Cooling=False "coolingpolicy/$POLICY" --timeout=120s
 [[ "$(k get node "$NODE" -o jsonpath='{.spec.taints}')" != *'rknetes.su/returned-from-roaming'* ]]
 k -n "$NS" logs "$SOLVER"
 k -n "$NS" get coolingpolicy "$POLICY" -o json
 k -n "$NS" delete coolingpolicy "$POLICY" --wait=true
 k -n "$NS" wait --for=delete "pod/$SOLVER" --timeout=60s
 echo "PASS: $scenario history automatically caused NoExecute eviction; blocked captcha delayed return, actual hash-verified fetch released it"
done
echo 'The persisted73-hour and previous-cluster records are controlled fixtures; no73-hour sleep or physical cluster migration is claimed'
