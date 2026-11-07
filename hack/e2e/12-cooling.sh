#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-cooling
new_namespace "$NS"
NODE=$(k get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}')
OLD_LAB=$(k get node "$NODE" -o jsonpath='{.metadata.labels.rknetes\.su/lab}')
restore() {
  k -n "$NS" patch coolingpolicy roaming --type merge -p '{"spec":{"captchaSolved":true}}' 2>/dev/null || true
  k taint node "$NODE" rknetes.su/returned-from-roaming- 2>/dev/null || true
  if [[ -n "$OLD_LAB" ]]; then k label node "$NODE" rknetes.su/lab="$OLD_LAB" --overwrite; else k label node "$NODE" rknetes.su/lab-; fi
}
trap restore EXIT
k label node "$NODE" rknetes.su/lab=true --overwrite
k -n "$NS" run traveller --image=busybox:1.37 --overrides="{\"spec\":{\"nodeName\":\"$NODE\"}}" --command -- sleep 3600
k -n "$NS" wait --for=condition=Ready pod/traveller --timeout=120s
k -n "$NS" apply -f - <<YAML
apiVersion: rknetes.su/v1alpha1
kind: CoolingPolicy
metadata: {name: roaming}
spec: {nodeName: $NODE, durationSeconds: 86400}
YAML
k -n "$NS" wait --for=condition=Cooling coolingpolicy/roaming --timeout=60s
k -n "$NS" wait --for=delete pod/traveller --timeout=90s
k -n "$NS" patch coolingpolicy roaming --type merge -p '{"spec":{"captchaSolved":true}}'
k -n "$NS" wait --for=condition=Cooling=False coolingpolicy/roaming --timeout=60s
[[ "$(k get node "$NODE" -o jsonpath='{.spec.taints[?(@.key=="rknetes.su/returned-from-roaming")].effect}')" == '' ]]
echo 'PASS: NoExecute evicted a real Pod and captcha completion removed the taint'
