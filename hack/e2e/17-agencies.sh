#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-agencies
new_namespace "$NS"
start=$(date +%s)
k -n "$NS" create -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata: {name: application, annotations: {rknetes.su/agency-delay: 2s}}
spec:
  containers: [{name: main, image: busybox:1.37, command: [sleep, '60']}]
YAML
elapsed=$(( $(date +%s)-start ))
[[ $elapsed -ge 2 && $elapsed -lt 17 ]]
printf 'PASS: validating agencies run in parallel; elapsed=%ss, sequential prediction=34s\n' "$elapsed"
