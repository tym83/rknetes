#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-whitelist-schedule
new_namespace "$NS"
start_lab_controller
trap stop_lab_controller EXIT
fixture foreign
client
IP=$(k -n "$NS" get pod foreign -o jsonpath='{.status.podIP}')
probe "http://$IP:8080"
k -n "$NS" apply -f - <<'YAML'
apiVersion: rknetes.su/v1alpha1
kind: WhitelistMode
metadata: {name: mobile}
spec: {enabled: true, periodSeconds: 20, activePercent: 60}
YAML
python3 - "$NS" "$IP" <<'PY'
import json,os,subprocess,sys,time
ns,ip=sys.argv[1:];start=time.monotonic();previous=start;last=None;durations={True:0.0,False:0.0};transitions=[]
while time.monotonic()-start<80:
 result=subprocess.run(['/work/bin/kubectl','--kubeconfig',os.environ['KUBECONFIG'],'--context','admin@workshop','-n',ns,'exec','client','--','wget','-q','-T','1','-O','/dev/null','http://'+ip+':8080'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=5)
 now=time.monotonic();blocked=result.returncode!=0
 if last is not None:durations[last]+=now-previous
 if last!=blocked:transitions.append({'elapsed':round(now-start,2),'blocked':blocked})
 previous=now;last=blocked;time.sleep(.5)
ratio=durations[True]/sum(durations.values())
print(json.dumps({'observedBlockedFraction':ratio,'seconds':{str(k):v for k,v in durations.items()},'transitions':transitions},indent=2))
assert .45<=ratio<=.75,ratio
assert len(transitions)>=7,transitions
PY
k -n "$NS" patch whitelistmode mobile --type merge -p '{"spec":{"enabled":false}}'
wait_until probe "http://$IP:8080"
NODE=$(k get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[1].metadata.name}')
NS_UID=$(k get namespace "$NS" -o jsonpath='{.metadata.uid}')
k label node "$NODE" rknetes.su/lab=true --overwrite
k annotate node "$NODE" rknetes.su/home-policy="$NS_UID" --overwrite
k taint node "$NODE" rknetes.su/whitelist-not-planned:NoSchedule
trap 'k taint node "$NODE" rknetes.su/whitelist-not-planned- || true; k annotate node "$NODE" rknetes.su/home-policy- || true; k delete clusterrolebinding/rknet-home-office clusterrole/rknet-home-office --ignore-not-found; stop_lab_controller' EXIT
k -n "$NS" run home-user --image=busybox:1.37 --overrides="{\"spec\":{\"nodeName\":\"$NODE\"}}" --command -- sleep 3600
k -n "$NS" wait --for=condition=Ready pod/home-user --timeout=120s
SHA=$(sha256sum /work/out/optional/home-office | cut -d' ' -f1)
k -n "$NS" apply -f - <<YAML
apiVersion: v1
kind: ServiceAccount
metadata: {name: home-office}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: {name: rknet-home-office}
rules:
- apiGroups: ['']
  resources: [nodes, namespaces, configmaps]
  verbs: [get]
- apiGroups: ['']
  resources: [nodes]
  resourceNames: [$NODE]
  verbs: [patch]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: {name: rknet-home-office}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: rknet-home-office}
subjects: [{kind: ServiceAccount, name: home-office, namespace: $NS}]
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: unplanned-inspection
  annotations: {rknetes.su/official-schedule: classified}
spec:
  schedule: '0 0 * * 0'
  timeZone: Etc/UTC
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      backoffLimit: 0
      template:
        spec:
          serviceAccountName: home-office
          restartPolicy: Never
          tolerations: [{key: rknetes.su/whitelist-not-planned, operator: Exists}]
          initContainers:
          - name: binary
            image: busybox:1.37
            command: [sh, -ec, "wget -q -O /rk/home-office http://10.244.8.11:8080/optional/home-office; echo '$SHA  /rk/home-office' | sha256sum -c -; chmod +x /rk/home-office"]
            volumeMounts: [{name: bin, mountPath: /rk}]
          containers:
          - name: office
            image: busybox:1.37
            command: [/rk/home-office, --node, $NODE, --namespace, $NS]
            volumeMounts: [{name: bin, mountPath: /rk}]
          volumes: [{name: bin, emptyDir: {}}]
YAML
k -n "$NS" create job inspection-now --from=cronjob/unplanned-inspection
k -n "$NS" wait --for=condition=Complete job/inspection-now --timeout=180s
k -n "$NS" logs job/inspection-now -c office
k -n "$NS" wait --for=delete pod/home-user --timeout=90s
[[ "$(k get node "$NODE" -o jsonpath='{.spec.taints[?(@.key=="rknetes.su/whitelist-not-planned")].effect}')" == NoExecute ]]
echo 'PASS: measured 60-percent duty cycle and a valid scheduled inspection evicted the home Pod'
