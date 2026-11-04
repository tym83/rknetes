#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-telegram-cycle
new_namespace "$NS"
trap 'k delete clusterrolebinding lab-telegram-guard --ignore-not-found; k delete clusterrole lab-telegram-guard --ignore-not-found' EXIT
files=${RK_FILES_IP:-10.244.8.11}
[[ "$files" == 10.244.* ]]
python3 - "$NS" "$files" <<'PY' | k apply -f -
import json,sys,copy
ns,files=sys.argv[1:]
def obj(api,kind,name,**kw):return {'apiVersion':api,'kind':kind,'metadata':{'name':name,'namespace':ns},**kw}
objects=[obj('v1','ServiceAccount','telegram')]
objects.append(obj('rbac.authorization.k8s.io/v1','Role','telegram',rules=[{'apiGroups':['rknetes.su'],'resources':['reestrentries','throttlepolicies'],'verbs':['get','create','update','patch']}]))
objects.append(obj('rbac.authorization.k8s.io/v1','RoleBinding','telegram',roleRef={'apiGroup':'rbac.authorization.k8s.io','kind':'Role','name':'telegram'},subjects=[{'kind':'ServiceAccount','name':'telegram','namespace':ns}]))
objects.append({'apiVersion':'rbac.authorization.k8s.io/v1','kind':'ClusterRole','metadata':{'name':'lab-telegram-guard'},'rules':[{'apiGroups':[''],'resources':['namespaces'],'resourceNames':[ns],'verbs':['get']},{'apiGroups':[''],'resources':['configmaps'],'resourceNames':['rknetes-stand'],'verbs':['get']}]})
objects.append({'apiVersion':'rbac.authorization.k8s.io/v1','kind':'ClusterRoleBinding','metadata':{'name':'lab-telegram-guard'},'roleRef':{'apiGroup':'rbac.authorization.k8s.io','kind':'ClusterRole','name':'lab-telegram-guard'},'subjects':[{'kind':'ServiceAccount','name':'telegram','namespace':ns}]})
pod={'serviceAccountName':'telegram','initContainers':[{'name':'binary','image':'busybox:1.37','command':['sh','-ec',f'wget -q -O /bin/rk/telegram-office http://{files}:8080/optional/telegram-office; chmod +x /bin/rk/telegram-office'],'volumeMounts':[{'name':'bin','mountPath':'/bin/rk'}]}],'containers':[{'name':'telegram','image':'busybox:1.37','command':['/bin/rk/telegram-office'],'args':['--namespace',ns],'volumeMounts':[{'name':'bin','mountPath':'/bin/rk'}],'readinessProbe':{'httpGet':{'path':'/readyz','port':8080},'periodSeconds':2}}],'volumes':[{'name':'bin','emptyDir':{}}]}
objects.append(obj('v1','Pod','telegram',spec=copy.deepcopy(pod)))
pod['restartPolicy']='Never';pod['containers'][0].pop('readinessProbe');pod['containers'][0]['args']=['--namespace',ns,'--action','cycle']
objects.append(obj('batch/v1','CronJob','telegram-cycle',spec={'schedule':'0 0 18 6 *','timeZone':'Etc/UTC','concurrencyPolicy':'Forbid','jobTemplate':{'spec':{'backoffLimit':0,'template':{'spec':pod}}}}))
print(json.dumps({'apiVersion':'v1','kind':'List','items':objects}))
PY
k -n "$NS" wait --for=condition=Ready pod/telegram --timeout=120s
readiness() { k -n "$NS" exec telegram -- wget -q -O - http://127.0.0.1:8080/readyz; }
[[ "$(readiness)" == ok ]]
k -n "$NS" apply -f - <<'YAML'
apiVersion: rknetes.su/v1alpha1
kind: ReestrEntry
metadata: {name: telegram}
spec: {podName: telegram}
YAML
k -n "$NS" wait --for=condition=Applied reestrentry/telegram --timeout=60s
[[ "$(readiness)" == '🛩' ]]
k -n "$NS" wait --for=condition=Ready pod/telegram --timeout=30s
k -n "$NS" annotate pod telegram rknetes.su/ready-to-counter-terrorism=true
normal() { [[ "$(readiness)" == ok ]]; }
wait_until normal
for year in 2027 2026; do
  patch=$(python3 - "$NS" "$year" <<'PY'
import json,sys
print(json.dumps([{'op':'replace','path':'/spec/jobTemplate/spec/template/spec/containers/0/args','value':['--namespace',sys.argv[1],'--action','cycle','--year',sys.argv[2]]}]))
PY
)
  k -n "$NS" patch cronjob telegram-cycle --type json -p "$patch"
  k -n "$NS" create job "cycle-$year" --from=cronjob/telegram-cycle
  k -n "$NS" wait --for=condition=Complete "job/cycle-$year" --timeout=120s
  k -n "$NS" logs "job/cycle-$year"
  if [[ "$year" == 2027 ]]; then ! k -n "$NS" get throttlepolicy telegram-cycle; fi
done
k -n "$NS" wait --for=condition=Applied throttlepolicy/telegram-cycle --timeout=60s
[[ "$(k -n "$NS" get pod telegram -o jsonpath='{.metadata.annotations.kubernetes\.io/egress-bandwidth}')" == 1M ]]
# Remove the controlled clock override from the retained production schedule.
patch=$(python3 - "$NS" <<'PY'
import json,sys
print(json.dumps([{'op':'replace','path':'/spec/jobTemplate/spec/template/spec/containers/0/args','value':['--namespace',sys.argv[1],'--action','cycle']}]))
PY
)
k -n "$NS" patch cronjob telegram-cycle --type json -p "$patch"
k -n "$NS" get cronjob telegram-cycle -o jsonpath='{.spec.schedule}{" "}{.spec.timeZone}{"\n"}'
echo 'PASS: registry-driven airplane readiness, annotation amnesty, real annual CronJob and six-year guard (2027 skipped, 2026 applied bandwidth)'
