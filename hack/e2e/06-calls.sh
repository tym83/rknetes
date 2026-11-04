#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-calls
new_namespace "$NS"
client
k -n "$NS" exec client -- echo allowed-before-policy
k -n "$NS" apply -f - <<'YAML'
apiVersion: rknetes.su/v1alpha1
kind: CallRestriction
metadata: {name: fraud}
spec: {enabled: true}
YAML
if k -n "$NS" exec client -- echo must-not-run > /tmp/rknet-calls.out 2>&1; then cat /tmp/rknet-calls.out; exit 1; fi
grep -q 'Звонки ограничены' /tmp/rknet-calls.out
echo 'PASS: real pod exec CONNECT denied by admission'
