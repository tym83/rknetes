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
python3 - "$NS" <<'PY'
import subprocess,sys
base=['kubectl','--context','admin@workshop','-n',sys.argv[1],'--request-timeout=8s']
for call in [['attach','client'],['port-forward','pod/client','19082:8080']]:
    result=subprocess.run(base+call,capture_output=True,text=True,timeout=12)
    assert result.returncode!=0 and 'Звонки ограничены' in result.stderr,(call,result.returncode,result.stdout,result.stderr)
    print('PASS: actual '+call[0]+' CONNECT refused by call admission')
PY
echo 'PASS: real pod exec, attach and port-forward CONNECT denied by admission'
