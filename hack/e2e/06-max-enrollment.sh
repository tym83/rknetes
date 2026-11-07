#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-max-security
new_namespace "$NS"
fixture target
PRIVATE=$(mktemp -d /work/tls/max-security.XXXXXX)
PREFIX=/work/kube/$(basename "$PRIVATE")
SERVER=
cleanup() { [[ -z "$SERVER" ]] || kill "$SERVER" 2>/dev/null || true; }
trap cleanup EXIT
python3 - "$PRIVATE" <<'PY'
import base64,json,pathlib,subprocess,sys,os,ssl
p=pathlib.Path(sys.argv[1]);p.chmod(0o700)
c=json.loads(subprocess.check_output(['kubectl','--context','admin@workshop','config','view','--raw','--minify','-o','json']))
for value,name in [(c['users'][0]['user']['client-certificate-data'],'client.crt'),(c['users'][0]['user']['client-key-data'],'client.key'),(c['clusters'][0]['cluster']['certificate-authority-data'],'ca.crt')]:
 target=p/name;target.write_bytes(base64.b64decode(value));target.chmod(0o600)
(p/'factor').write_bytes(os.urandom(32));(p/'factor').chmod(0o600)
subject=dict(pair for field in ssl._ssl._test_decode_cert(str(p/'client.crt'))['subject'] for pair in field)
(p/'identity').write_text(subject['commonName'])
PY
k -n "$NS" create configmap max-enrollments --from-literal="rk-max-worker=$(cat "$PRIVATE/identity")"
/work/out/optional/maxlet --kubeconfig "$KUBECONFIG" --context admin@workshop --listen 127.0.0.1:19446 \
 --tls-cert "$RK_TLS_DIR/maxlet/tls.crt" --tls-key "$RK_TLS_DIR/maxlet/tls.key" --client-ca "$PRIVATE/ca.crt" \
 --archive "$PRIVATE/archive" --second-factor-secret "$PRIVATE/factor" --session-ttl 20s --enrollment-namespace "$NS" > /work/tmp/max-security.log 2>&1 &
SERVER=$!
sleep 2
export HODATAY_MAX_SERVER=https://127.0.0.1:19446 HODATAY_MAX_CA="$RK_TLS_DIR/maxlet/tls.crt" HODATAY_KUBECTL=/work/bin/kubectl HODATAY_MAX_SESSION_FILE="$PRIVATE/session"
export HODATAY_MAX_CODE=$(python3 - "$PRIVATE" <<'PY'
import hmac,hashlib,time,struct,sys,pathlib
s=(pathlib.Path(sys.argv[1])/'factor').read_bytes();d=hmac.new(s,struct.pack('>Q',int(time.time())//30),hashlib.sha1).digest();o=d[-1]&15
print(f'{(struct.unpack(">I",d[o:o+4])[0]&0x7fffffff)%1000000:06d}')
PY
)
/work/out/optional/max-login --kubeconfig "$KUBECONFIG" --context admin@workshop --output "$PRIVATE/session"
if /work/out/optional/max-login --kubeconfig "$KUBECONFIG" --context admin@workshop --output "$PRIVATE/replayed-session"; then exit 1; fi
unset HODATAY_MAX_CODE
/work/out/optional/hodatay max --context admin@workshop -n "$NS" exec target -- echo real-second-factor-call
enroll() { /work/out/optional/max-enroll --kubeconfig "$KUBECONFIG" --context admin@workshop --node-kubeconfig /work/kube/node.conf --node-server https://10.244.8.31:50000 --max-server "$HODATAY_MAX_SERVER" --max-ca "$HODATAY_MAX_CA" --session-file "$PRIVATE/session" "$@"; }
if enroll --node-name rk-unenrolled --output ${PREFIX}-refused.yaml --failure-policy Open; then exit 1; fi
[[ ! -e ${PREFIX}-refused.yaml ]]
enroll --node-name rk-max-worker --output ${PREFIX}-enrolled.yaml
k -n "$NS" delete configmap max-enrollments
if enroll --node-name rk-max-worker --output ${PREFIX}-closed.yaml; then exit 1; fi
[[ ! -e ${PREFIX}-closed.yaml ]]
enroll --node-name rk-max-worker --output ${PREFIX}-open.yaml --failure-policy Open
for file in ${PREFIX}-enrolled.yaml ${PREFIX}-open.yaml; do
 [[ $(stat -c %a "$file") == 600 ]]; [[ $(wc -c < "$file") -gt 1000 ]]
done
k -n "$NS" apply -f - <<YAML
apiVersion: v1
kind: Event
metadata: {name: max-observed}
involvedObject: {apiVersion: v1, kind: Pod, name: target, namespace: $NS}
reason: MaxEvidence
message: Controlled nested Event for private MAX archive proof
type: Normal
YAML
observed() { python3 - "$PRIVATE" <<'PY'
import pathlib,json,sys
events=[json.loads(x) for x in (pathlib.Path(sys.argv[1])/'archive/events.jsonl').read_text().splitlines()]
assert any(x.get('metadata',{}).get('name')=='max-observed' for x in events)
namespaces={x.get('metadata',{}).get('namespace') for x in events}
assert 'lab-max-security' in namespaces and len(namespaces)>1
print('PASS: actual event archived; observed nested namespaces',len(namespaces),'events',len(events))
PY
}
wait_until observed
sleep 21
if /work/out/optional/hodatay max --context admin@workshop -n "$NS" exec target -- echo should-expire; then exit 1; fi
python3 - "$PRIVATE" <<'PY'
import http.client,ssl,sys,pathlib
p=pathlib.Path(sys.argv[1]);ctx=ssl.create_default_context(cafile='/work/tls/maxlet/tls.crt');ctx.load_cert_chain(p/'client.crt',p/'client.key')
c=http.client.HTTPSConnection('127.0.0.1',19446,context=ctx);c.request('GET','/version');assert c.getresponse().status==401;c.close()
assert any('"direction":"server"' in f.read_text() for f in (p/'archive').glob('call-*.jsonl'))
print('PASS: certificate alone denied; real upgraded stream bytes archived without exporting private archive')
PY
echo 'PASS: real JoinTickets require MAX enrollment; explicit fail-open covers503 only; denial stays closed; session replay/expiry and all-Events archive proved'
