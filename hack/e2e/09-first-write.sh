#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-data-boundary
new_namespace "$NS"
k label ns "$NS" pod-security.kubernetes.io/enforce=privileged
trap 'k delete clusterrolebinding lab-boundary-guard --ignore-not-found; k delete clusterrole lab-boundary-guard --ignore-not-found' EXIT
password=$(openssl rand -hex 24)
k -n "$NS" create secret generic db-auth --from-literal=password="$password"
unset password
mapfile -t nodes < <(k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
uid=$(k get namespace "$NS" -o jsonpath='{.metadata.uid}')
files=${RK_FILES_IP:-10.244.8.11}
[[ "$files" == 10.244.* ]]
python3 - "$NS" "${nodes[0]}" "${nodes[1]}" "$uid" "$files" <<'PY' | k apply -f -
import json,sys
ns,domestic,foreign,uid,files=sys.argv[1:]
def obj(api,kind,name,**kw):return {'apiVersion':api,'kind':kind,'metadata':{'name':name,'namespace':ns},**kw}
objects=[]
password={'name':'POSTGRES_PASSWORD','valueFrom':{'secretKeyRef':{'name':'db-auth','key':'password'}}}
for name,node in [('ru-primary',domestic),('replica',foreign)]:
    service=obj('v1','Service',name,spec={'selector':{'app':name},'ports':[{'port':5432}]});service['metadata']['labels']={'rknetes.su/labdb':'true'};objects.append(service)
    spec={'serviceName':name,'replicas':1,'selector':{'matchLabels':{'app':name}},'template':{'metadata':{'labels':{'app':name}},'spec':{'nodeName':node,'automountServiceAccountToken':False,'containers':[{'name':'postgres','image':'postgres:17@sha256:3b0cda93be7c8dba2ed484d19393d93845dc3dafb88973e248ba8e6d99d784e1','args':['-c','shared_buffers=32MB','-c','max_connections=30'],'env':[password],'resources':{'requests':{'cpu':'100m','memory':'128Mi'},'limits':{'memory':'512Mi'}},'readinessProbe':{'exec':{'command':['pg_isready','-U','postgres']},'periodSeconds':2},'volumeMounts':[{'name':'data','mountPath':'/var/lib/postgresql/data'}]}],'volumes':[{'name':'data','hostPath':{'path':f'/var/lib/rknetes/data-boundary/{uid}/{name}','type':'DirectoryOrCreate'}}]}}}
    objects.append(obj('apps/v1','StatefulSet',name,spec=spec))
objects.append(obj('v1','ServiceAccount','boundary'))
objects.append(obj('rbac.authorization.k8s.io/v1','Role','boundary',rules=[{'apiGroups':['rknetes.su'],'resources':['databoundarypolicies'],'verbs':['get','list']},{'apiGroups':['rknetes.su'],'resources':['databoundarypolicies/status'],'verbs':['patch']},{'apiGroups':['apps'],'resources':['statefulsets'],'verbs':['get']},{'apiGroups':[''],'resources':['services'],'verbs':['get']}]))
objects.append(obj('rbac.authorization.k8s.io/v1','RoleBinding','boundary',roleRef={'apiGroup':'rbac.authorization.k8s.io','kind':'Role','name':'boundary'},subjects=[{'kind':'ServiceAccount','name':'boundary','namespace':ns}]))
objects.append({'apiVersion':'rbac.authorization.k8s.io/v1','kind':'ClusterRole','metadata':{'name':'lab-boundary-guard'},'rules':[{'apiGroups':[''],'resources':['namespaces'],'resourceNames':[ns],'verbs':['get']},{'apiGroups':[''],'resources':['configmaps'],'resourceNames':['rknetes-stand'],'verbs':['get']}]})
objects.append({'apiVersion':'rbac.authorization.k8s.io/v1','kind':'ClusterRoleBinding','metadata':{'name':'lab-boundary-guard'},'roleRef':{'apiGroup':'rbac.authorization.k8s.io','kind':'ClusterRole','name':'lab-boundary-guard'},'subjects':[{'kind':'ServiceAccount','name':'boundary','namespace':ns}]})
app=obj('apps/v1','StatefulSet','orders',spec={'serviceName':'orders','replicas':1,'selector':{'matchLabels':{'app':'orders'}},'template':{'metadata':{'labels':{'app':'orders'}},'spec':{'nodeName':foreign,'serviceAccountName':'boundary','initContainers':[{'name':'binary','image':'busybox:1.37','command':['sh','-ec',f'wget -q -O /bin/rk/first-write http://{files}:8080/optional/first-write; chmod +x /bin/rk/first-write'],'volumeMounts':[{'name':'bin','mountPath':'/bin/rk'}]}],'containers':[{'name':'adapter','image':'busybox:1.37','command':['/bin/rk/first-write','--namespace',ns],'env':[{'name':'PGPASSWORD','valueFrom':{'secretKeyRef':{'name':'db-auth','key':'password'}}}],'volumeMounts':[{'name':'bin','mountPath':'/bin/rk'}],'readinessProbe':{'httpGet':{'path':'/healthz','port':8080},'periodSeconds':2}}],'volumes':[{'name':'bin','emptyDir':{}}]}}});app['metadata']['labels']={'app':'orders'};objects.append(app)
objects.append(obj('v1','Service','orders',spec={'selector':{'app':'orders'},'ports':[{'port':8080}]}))
objects.append(obj('rknetes.su/v1alpha1','DataBoundaryPolicy','orders',spec={'selector':{'app':'orders'},'primaryService':'ru-primary'}))
for name in ['orders','replica']:
    objects.append(obj('rknetes.su/v1alpha1','SociallySignificantResource',name,spec={'serviceName':name,'selector':{'app':name},'approved':True}))
objects.append(obj('cilium.io/v2','CiliumNetworkPolicy','adapter-api',spec={'endpointSelector':{'matchLabels':{'app':'orders'}},'enableDefaultDeny':{'ingress':False,'egress':False},'egress':[{'toEntities':['kube-apiserver']}]}))
print(json.dumps({'apiVersion':'v1','kind':'List','items':objects}))
PY
for name in ru-primary replica orders; do k -n "$NS" rollout status "statefulset/$name" --timeout=240s; done
k -n "$NS" run client --image=nicolaka/netshoot:v0.14 --command -- sleep 1800
k -n "$NS" wait --for=condition=Ready pod/client --timeout=120s
python3 - <<'PY'
import subprocess,json,time,datetime
base=['kubectl','--context','admin@workshop','-n','lab-data-boundary']
def k(*args):return subprocess.check_output(base+list(args))
def post(i):
    raw=k('exec','client','--','curl','-sS','--max-time','12','-w','\n%{http_code}','-H','Content-Type: application/json','-d',json.dumps({'id':i,'value':f'order-{i}'}),'http://orders:8080/write').decode()
    body,code=raw.rsplit('\n',1);body=json.loads(body);print(code,body,flush=True);return int(code),body
def count(db):return int(k('exec',db+'-0','--','psql','-U','postgres','-tAc','SELECT count(*) FROM writes').strip())
code,body=post(1);assert code==201 and body['primaryCommitted'] and body['replicaCommitted']
assert body['primaryCommitObservedAt']<=body['replicaWriteStartedAt']
assert count('ru-primary')==count('replica')==1
assert k('exec','ru-primary-0','--','psql','-U','postgres','-tAc','SHOW fsync').strip()==b'on'
k('delete','pod','ru-primary-0','--wait=true')
k('wait','--for=condition=Ready','pod/ru-primary-0','--timeout=120s')
assert count('ru-primary')==1
policy={'apiVersion':'rknetes.su/v1alpha1','kind':'WhitelistMode','metadata':{'name':'localize'},'spec':{'enabled':True,'integrity':False}}
subprocess.run(base+['apply','-f','-'],input=json.dumps(policy).encode(),check=True)
for _ in range(30):
    p=subprocess.run(base+['get','ciliumnetworkpolicy','whitelist'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    if p.returncode==0:break
    time.sleep(1)
else:raise AssertionError('whitelist was not installed')
time.sleep(3)
code,body=post(2);assert code==503 and not body['primaryCommitted'] and not body['replicaCommitted'] and 'no replica write attempted' in body['failure']
assert count('ru-primary')==count('replica')==1
assert k('exec','client','--','curl','-fsS','http://orders:8080/healthz')==b'ok'
k('patch','whitelistmode','localize','--type','merge','-p','{"spec":{"enabled":false}}')
k('wait','--for=delete','ciliumnetworkpolicy/whitelist','--timeout=60s')
code,body=post(3);assert code==201 and count('ru-primary')==count('replica')==2
primary={'apiVersion':'rknetes.su/v1alpha1','kind':'SociallySignificantResource','metadata':{'name':'ru-primary'},'spec':{'serviceName':'ru-primary','selector':{'app':'ru-primary'},'approved':True}}
subprocess.run(base+['apply','-f','-'],input=json.dumps(primary).encode(),check=True)
k('patch','socialresources','replica','--type','merge','-p','{"spec":{"approved":false}}')
k('patch','whitelistmode','localize','--type','merge','-p','{"spec":{"enabled":true}}')
# Wait for the controller to reinstall the policy and for Cilium to apply it, as above.
for _ in range(30):
    p=subprocess.run(base+['get','ciliumnetworkpolicy','whitelist'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    if p.returncode==0:break
    time.sleep(1)
else:raise AssertionError('whitelist was not reinstalled')
time.sleep(5)
code,body=post(4);assert code==503 and body['primaryCommitted'] and not body['replicaCommitted']
assert count('ru-primary')==3 and count('replica')==2
k('patch','whitelistmode','localize','--type','merge','-p','{"spec":{"enabled":false}}')
k('wait','--for=delete','ciliumnetworkpolicy/whitelist','--timeout=60s')
code,body=post(4);assert code==201 and count('ru-primary')==count('replica')==3
print('PASS: durable primary commit precedes replication; primary restart preserves data; whitelist blocks primary writes while readiness stays green; partial replication failure and idempotent retry measured')
PY
k -n "$NS" get pods -o json | python3 -c 'import json,sys;print(json.dumps([{ "name":p["metadata"]["name"],"node":p["spec"].get("nodeName"),"images":[c.get("imageID") for c in p["status"].get("containerStatuses",[])]} for p in json.load(sys.stdin)["items"]],indent=2))'
