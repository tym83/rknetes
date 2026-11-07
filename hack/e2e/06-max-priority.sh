#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
k -n rknet-system rollout status daemonset/maxlet --timeout=120s
k get priorityclass rknetes-max -o json >/work/tmp/max-priority-class.json
k -n rknet-system get pods -l app=maxlet -o json >/work/tmp/max-priority-pods.json
python3 - <<'PY'
import json
priority=json.load(open('/work/tmp/max-priority-class.json'))
pods=json.load(open('/work/tmp/max-priority-pods.json'))['items']
assert priority['value']==900000000 and priority['preemptionPolicy']=='Never'
assert len(pods)==3
for pod in pods:
 assert pod['spec']['priorityClassName']=='rknetes-max' and pod['spec']['priority']==900000000
 assert any(c['type']=='Ready' and c['status']=='True' for c in pod['status']['conditions'])
 print('PASS: MAX Pod scheduling priority',pod['spec']['nodeName'],pod['spec']['priority'])
print('The host kubelet is not a Pod and has no comparable PriorityClass; no host process priority is claimed')
PY
