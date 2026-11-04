#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-blogger
new_namespace "$NS"
k -n "$NS" create configmap channel --from-literal=message=initial
k -n "$NS" apply -f - <<'YAML'
apiVersion: rknetes.su/v1alpha1
kind: BloggerRegistration
metadata: {name: channel}
spec: {resource: configmaps, name: channel, registered: false, threshold: 3}
YAML
k -n rknet-system rollout status deployment/watch-office --timeout=120s
k -n rknet-system port-forward service/watch-office 19444:443 > /tmp/rknetes-watch-forward.log 2>&1 &
forward=$!
private=$(mktemp -d /work/tls/watch-client.XXXXXX)
trap 'kill "$forward" 2>/dev/null || true; rm -rf "$private"' EXIT
sleep 2
python3 - "$private" <<'PY'
import base64,json,pathlib,subprocess,sys
p=pathlib.Path(sys.argv[1]);p.chmod(0o700)
c=json.loads(subprocess.check_output(['kubectl','--context','admin@workshop','config','view','--raw','--minify','-o','json']))
u=c['users'][0]['user']
for field,name in [('client-certificate-data','client.crt'),('client-key-data','client.key')]:
    target=p/name;target.write_bytes(base64.b64decode(u[field]));target.chmod(0o600)
PY
python3 - "$private" <<'PY'
import http.client,ssl,sys,subprocess,time
ctx=ssl.create_default_context(cafile='/work/tls/watch/tls.crt')
ctx.load_cert_chain(sys.argv[1]+'/client.crt',sys.argv[1]+'/client.key')
path='/api/v1/namespaces/lab-blogger/configmaps?watch=true&fieldSelector=metadata.name%3Dchannel&resourceVersion=0&timeoutSeconds=60'
connections=[]
def watch():
    c=http.client.HTTPSConnection('127.0.0.1',19444,context=ctx,timeout=15);connections.append(c)
    c.request('GET',path);return c.getresponse()
try:
    for _ in range(3):
        r=watch();assert r.status==200,r.read()
        assert b'"type":"ADDED"' in r.readline()
    r=watch();assert r.status==451,(r.status,r.read())
    assert b'4 active watches exceed 3' in r.read()
    subprocess.run(['kubectl','--context','admin@workshop','-n','lab-blogger','patch','bloggerregistration','channel','--type','merge','-p','{"spec":{"registered":true}}'],check=True)
    r=watch();assert r.status==200,r.read()
    assert b'"type":"ADDED"' in r.readline()
    print('PASS: four real concurrent watches crossed the threshold; HTTP 451 until registration; registered watch resumed')
finally:
    for c in connections:c.close()
PY
k -n "$NS" get bloggerregistration channel -o jsonpath='{.status.observedConcurrentWatches}' | grep '^4$'
