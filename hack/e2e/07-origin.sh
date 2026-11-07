#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-origin
new_namespace "$NS"
fixture original
DIGEST=$(k -n "$NS" get pod original -o jsonpath='{.status.containerStatuses[0].imageID}' | sed 's/.*@//')
[[ "$DIGEST" == sha256:* ]]
k -n "$NS" apply -f - <<YAML
apiVersion: rknetes.su/v1alpha1
kind: ForeignAgentPolicy
metadata: {name: digest}
spec: {enabled: true, digests: ['$DIGEST']}
YAML
k -n "$NS" run domestic --image="registry.goshran.svc/native@$DIGEST" --dry-run=server -o json > /tmp/rknet-origin.json
python3 - <<'PY'
import json
p=json.load(open('/tmp/rknet-origin.json'))
assert p['metadata']['labels']['rknetes.su/inoagent']=='true'
print('PASS: retagged real image digest admitted as a foreign agent')
PY
