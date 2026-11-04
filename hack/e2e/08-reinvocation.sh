#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-reinvocation
new_namespace "$NS"
k label namespace "$NS" rknetes.su/reinvocation-experiment=true
private=$(mktemp -d /work/tls/reinvocation.XXXXXX)
trap 'k delete mutatingwebhookconfiguration lab-substitution --ignore-not-found; rm -rf "$private"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -keyout "$private/tls.key" -out "$private/tls.crt" -subj /CN=substitution -addext "subjectAltName=DNS:substitution.$NS.svc" >/dev/null 2>&1
k -n "$NS" create secret tls serving --cert="$private/tls.crt" --key="$private/tls.key"
files=${RK_FILES_IP:-10.244.8.11}
[[ "$files" == 10.244.* ]]
k -n "$NS" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: substitution, labels: {app: substitution}}
spec:
  automountServiceAccountToken: false
  initContainers:
  - name: binary
    image: busybox:1.37
    command: [sh, -ec, 'wget -q -O /bin/rk/substitution-office http://$files:8080/optional/substitution-office; chmod +x /bin/rk/substitution-office']
    volumeMounts: [{name: bin, mountPath: /bin/rk}]
  containers:
  - name: server
    image: busybox:1.37
    command: [/bin/rk/substitution-office]
    volumeMounts: [{name: bin, mountPath: /bin/rk}, {name: tls, mountPath: /tls, readOnly: true}]
  volumes: [{name: bin, emptyDir: {}}, {name: tls, secret: {secretName: serving}}]
---
apiVersion: v1
kind: Service
metadata: {name: substitution}
spec: {selector: {app: substitution}, ports: [{port: 443, targetPort: 9443}]}
YAML
k -n "$NS" wait --for=condition=Ready pod/substitution --timeout=120s
ca=$(base64 -w0 < "$private/tls.crt")
python3 - "$NS" "$ca" <<'PY' | k apply -f -
import json,sys
ns,ca=sys.argv[1:]
hooks=[]
for name,path,reinvoke in [('substitute','/substitute','IfNeeded'),('next-agency','/next-agency','Never')]:
    hooks.append({'name':name+'.research.rknetes.su','admissionReviewVersions':['v1'],'sideEffects':'None','failurePolicy':'Fail','timeoutSeconds':10,'reinvocationPolicy':reinvoke,'namespaceSelector':{'matchLabels':{'rknetes.su/reinvocation-experiment':'true'}},'clientConfig':{'service':{'name':'substitution','namespace':ns,'path':path},'caBundle':ca},'rules':[{'operations':['CREATE'],'apiGroups':[''],'apiVersions':['v1'],'resources':['pods'],'scope':'Namespaced'}]})
print(json.dumps({'apiVersion':'admissionregistration.k8s.io/v1','kind':'MutatingWebhookConfiguration','metadata':{'name':'lab-substitution'},'webhooks':hooks}))
PY
sleep 2
k -n "$NS" run imported --image=busybox:1.37 --command -- sleep 1800
k -n "$NS" wait --for=condition=Ready pod/imported --timeout=120s
k -n "$NS" get pod imported -o json | python3 -c 'import json,sys;p=json.load(sys.stdin);a=p["metadata"]["annotations"];assert a["rknetes.su/substitution-passes"]=="2",a;assert a["rknetes.su/next-agency"]=="reviewed";assert p["spec"]["containers"][0]["image"]=="busybox:1.37";print("PASS: original image unchanged; two reported substitutions, one reinvocation; Kubernetes stops the loop")'
k -n "$NS" logs substitution
