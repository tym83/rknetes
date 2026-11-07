#!/usr/bin/env python3
"""Render the scoped native-network agent without any credentials."""
import json,os
items=[]
def add(api,kind,name,ns=None,**fields):
 m={'name':name,'labels':{'rknetes.su/managed':'true'}}
 if ns:m['namespace']=ns
 o={'apiVersion':api,'kind':kind,'metadata':m,**fields};items.append(o)
add('v1','ServiceAccount','tspu','rknet-system')
add('rbac.authorization.k8s.io/v1','ClusterRole','tspu',rules=[
 {'apiGroups':[''],'resources':['namespaces','pods','configmaps'],'verbs':['get','list']},
 {'apiGroups':['rknetes.su'],'resources':['sovereignbytepolicies'],'verbs':['get','list']},
 {'apiGroups':['rknetes.su'],'resources':['sovereignbytepolicies/status'],'verbs':['patch']}])
add('rbac.authorization.k8s.io/v1','ClusterRoleBinding','tspu',roleRef={'apiGroup':'rbac.authorization.k8s.io','kind':'ClusterRole','name':'tspu'},subjects=[{'kind':'ServiceAccount','name':'tspu','namespace':'rknet-system'}])
# The cluster's highest role. RBAC has no "except", so its holders are refused at
# admission instead: on the TSPU agent their rights are not enough. Whose are, is not stated.
add('rbac.authorization.k8s.io/v1','ClusterRole','cluster-admin-ponyatno-kto',rules=[
 {'apiGroups':['*'],'resources':['*'],'verbs':['*']},{'nonResourceURLs':['*'],'verbs':['*']}])
add('rbac.authorization.k8s.io/v1','ClusterRoleBinding','cluster-admin-ponyatno-kto',roleRef={'apiGroup':'rbac.authorization.k8s.io','kind':'ClusterRole','name':'cluster-admin-ponyatno-kto'},subjects=[{'apiGroup':'rbac.authorization.k8s.io','kind':'Group','name':'rknetes:ponyatno-kto'}])
add('admissionregistration.k8s.io/v1','ValidatingAdmissionPolicy','tspu-ponyatno-kto',spec={
 'failurePolicy':'Fail',
 'matchConstraints':{'namespaceSelector':{'matchLabels':{'kubernetes.io/metadata.name':'rknet-system'}},'resourceRules':[
  {'apiGroups':['apps'],'apiVersions':['v1'],'operations':['CREATE','UPDATE','DELETE'],'resources':['daemonsets']},
  {'apiGroups':[''],'apiVersions':['v1'],'operations':['CREATE','UPDATE','DELETE'],'resources':['pods']}]},
 'matchConditions':[{'name':'tspu','expression':"(request.operation == 'DELETE' ? oldObject : object).metadata.name == 'tspu' || (has((request.operation == 'DELETE' ? oldObject : object).metadata.labels) && (request.operation == 'DELETE' ? oldObject : object).metadata.labels.?app.orValue('') == 'tspu')"}],
 'validations':[{'expression':"!('rknetes:ponyatno-kto' in request.userInfo.groups)",
  'message':'Прав cluster-admin-ponyatno-kto на ТСПУ недостаточно. Чьих достаточно — не указано.','reason':'Forbidden'}]})
add('admissionregistration.k8s.io/v1','ValidatingAdmissionPolicyBinding','tspu-ponyatno-kto',spec={'policyName':'tspu-ponyatno-kto','validationActions':['Deny']})
image=os.environ['TSPU_IMAGE'];url=os.environ['TSPU_URL']
download='set -eu; '
for name,key in [('tspu','TSPU_SHA'),('tspu.o','TSPU_OBJECT_SHA')]:
 download+=f'wget -q -O /rk/{name} {url}/{name}; echo "{os.environ[key]}  /rk/{name}" | sha256sum -c -; '
download+='chmod 755 /rk/tspu'
add('apps/v1','DaemonSet','tspu','rknet-system',spec={'selector':{'matchLabels':{'app':'tspu'}},'template':{
 'metadata':{'labels':{'app':'tspu'},'annotations':{'rknetes.su/binary-sha256':os.environ['TSPU_SHA'],'rknetes.su/object-sha256':os.environ['TSPU_OBJECT_SHA']}},'spec':{
 'serviceAccountName':'tspu','hostPID':True,'tolerations':[{'operator':'Exists'}],
 'initContainers':[{'name':'binary','image':image,'command':['sh','-ec',download],'volumeMounts':[{'name':'bin','mountPath':'/rk'}]}],
 'containers':[{'name':'tspu','image':image,'command':['/rk/tspu'],'securityContext':{'privileged':True},
 'env':[{'name':'NODE_NAME','valueFrom':{'fieldRef':{'fieldPath':'spec.nodeName'}}}],
 'resources':{'requests':{'cpu':'25m','memory':'64Mi'},'limits':{'cpu':'1','memory':'256Mi'}},
 'volumeMounts':[{'name':'bin','mountPath':'/rk','readOnly':True},{'name':'cri','mountPath':'/run/containerd/containerd.sock','readOnly':True}]}],
 'volumes':[{'name':'bin','emptyDir':{}},{'name':'cri','hostPath':{'path':'/run/containerd/containerd.sock','type':'Socket'}}]}}})
print(json.dumps({'apiVersion':'v1','kind':'List','items':items}))
