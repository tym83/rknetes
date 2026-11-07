#!/usr/bin/env bash
# Opt-in public view: the same authenticated administrator sees two realities.
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-presentation
new_namespace "$NS"
k -n "$NS" create configmap presentation-policy --from-literal=mode=normal --from-literal=redact=true --from-literal=searchPenalty=true
k -n "$NS" apply -f - <<'YAML'
apiVersion: rknetes.su/v1alpha1
kind: TunnelProfile
metadata: {name: official, labels: {rknetes.su/official: "true"}}
spec: {protocolLadder: [WireGuard], compliant: true, target: lab}
---
apiVersion: rknetes.su/v1alpha1
kind: TunnelProfile
metadata: {name: wireguard}
spec: {protocolLadder: [WireGuard], target: lab}
YAML
k -n "$NS" run logger --image=busybox:1.37 --command -- sh -c 'for i in $(seq 1 200); do echo "GET / 200 VPN"; done; sleep 1800'
k -n "$NS" wait --for=condition=Ready pod/logger --timeout=120s
k -n "$NS" apply -f - <<'YAML'
apiVersion: v1
kind: ResourceQuota
metadata: {name: search-budget, labels: {rknetes.su/managed: "true"}}
spec: {hard: {requests.cpu: "8"}}
YAML
big_pod() {
  k -n "$NS" run four-cpu --image=busybox:1.37 --overrides='{"spec":{"containers":[{"name":"four-cpu","image":"busybox:1.37","command":["sleep","1800"],"resources":{"requests":{"cpu":"4"}}}]}}'
}
big_pod
k -n "$NS" delete pod four-cpu --wait=true
private=$(mktemp -d /work/tls/presentation-client.XXXXXX)
server=
trap '[[ -z "$server" ]] || kill "$server" 2>/dev/null || true; rm -rf "$private"' EXIT
python3 - "$private" <<'PY'
import base64,json,pathlib,subprocess,sys
p=pathlib.Path(sys.argv[1]);p.chmod(0o700)
c=json.loads(subprocess.check_output(['kubectl','--context','admin@workshop','config','view','--raw','--minify','-o','json']))
for value,name in [(c['users'][0]['user']['client-certificate-data'],'client.crt'),(c['users'][0]['user']['client-key-data'],'client.key'),(c['clusters'][0]['cluster']['certificate-authority-data'],'ca.crt')]:
    target=p/name;target.write_bytes(base64.b64decode(value));target.chmod(0o600)
PY
/work/out/optional/presentation-office --kubeconfig "$KUBECONFIG" --context admin@workshop --namespace "$NS" --listen 127.0.0.1:19445 --tls-cert /work/tls/watch/tls.crt --tls-key /work/tls/watch/tls.key --client-ca "$private/ca.crt" > /work/presentation-office.log 2>&1 &
server=$!
sleep 2
python3 - "$private" <<'PY'
import http.client,ssl,sys,subprocess,time,json,pathlib
root=pathlib.Path('/work/evidence/presentation-details');root.mkdir(exist_ok=True)
ctx=ssl.create_default_context(cafile='/work/tls/watch/tls.crt')
ctx.load_cert_chain(sys.argv[1]+'/client.crt',sys.argv[1]+'/client.key')
base='/apis/rknetes.su/v1alpha1/namespaces/lab-presentation/tunnelprofiles'
def get(path):
    c=http.client.HTTPSConnection('127.0.0.1',19445,context=ctx,timeout=15)
    try:
        c.request('GET',path);r=c.getresponse();return r.status,r.read()
    finally:c.close()
def k(*args):
    return subprocess.check_output(['kubectl','--context','admin@workshop','-n','lab-presentation',*args])
native=json.loads(k('get','tunnelprofiles','-o','json'))
assert {o['metadata']['name'] for o in native['items']}=={'official','wireguard'}
code,body=get(base)
assert code==200,(code,body)
public=json.loads(body)
assert len(public['items'])==1 and public['items'][0]['metadata']['name']=='[ДАННЫЕ УДАЛЕНЫ]',public
code,body=get(base+'/official');assert code==404,(code,body)
raw=k('logs','logger')
code,decorated=get('/api/v1/namespaces/lab-presentation/pods/logger/log')
assert code==200 and b'VPN' not in decorated and decorated.count('ДАННЫЕ УДАЛЕНЫ'.encode())==200
(root/'raw.log').write_bytes(raw);(root/'decorated.log').write_bytes(decorated)
assert len(decorated.splitlines())==400 and len(decorated)>len(raw)*20
code,body=get('/api/v1/namespaces/lab-presentation/pods/logger?presentation=banner')
assert code==200
envelope=json.loads(body);assert envelope['object']['metadata']['name']=='logger' and envelope['disclaimer']
(root/'api-presentation.json').write_bytes(body)
stats={'lines':200,'rawBytes':len(raw),'decoratedBytes':len(decorated),'amplification':len(decorated)/len(raw),'rawAllocatedBytes':(root/'raw.log').stat().st_blocks*512,'decoratedAllocatedBytes':(root/'decorated.log').stat().st_blocks*512}
(root/'storage.json').write_text(json.dumps(stats,indent=2)+'\n');print(json.dumps(stats))
code,body=get(base+'?search=wireguard');assert code==200,(code,body)
quota=json.loads(k('get','resourcequota','search-budget','-o','json'))
assert quota['spec']['hard']['requests.cpu']=='3'
code,body=get(base+'?search=wireguard');assert code==200
quota=json.loads(k('get','resourcequota','search-budget','-o','json'));assert quota['spec']['hard']['requests.cpu']=='3'
k('patch','configmap','presentation-policy','--type','merge','-p','{"data":{"mode":"destructive"}}')
for path in [base,'/version','/api/v1/namespaces/lab-presentation/pods/logger']:
    code,body=get(path);assert code==451,(path,code,body)
assert json.loads(k('get','pod','logger','-o','json'))['metadata']['name']=='logger'
k('patch','configmap','presentation-policy','--type','merge','-p','{"data":{"mode":"normal"}}')
code,body=get(base);assert code==200,(code,body)
print('PASS: authenticated public list hides official tunnel while native API exposes it; duplicated 24-word log banner, redaction, measured disk growth, 5000m fine and destructive 451 recovery')
PY
if big_pod > /tmp/rknetes-search-fine.log 2>&1; then echo 'quota penalty did not block a real Pod creation' >&2; exit 1; fi
grep 'exceeded quota' /tmp/rknetes-search-fine.log
echo 'PASS: CPU fine is enforced by actual ResourceQuota admission'
