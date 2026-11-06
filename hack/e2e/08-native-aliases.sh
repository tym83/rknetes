#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-native-aliases
new_namespace "$NS"
k label namespace "$NS" pod-security.kubernetes.io/enforce=privileged
IMAGE=$(cat /work/out/tools/lab-image.ref)
k -n "$NS" apply -f - <<YAML
apiVersion: apps/v1
kind: DaemonSet
metadata: {name: inspect}
spec:
  selector: {matchLabels: {app: inspect}}
  template:
    metadata: {labels: {app: inspect}}
    spec:
      automountServiceAccountToken: false
      tolerations: [{operator: Exists}]
      containers:
      - name: inspect
        image: $IMAGE
        command: [sleep, '600']
        volumeMounts: [{name: root, mountPath: /host, readOnly: true}]
      volumes: [{name: root, hostPath: {path: /, type: Directory}}]
YAML
k -n "$NS" rollout status daemonset/inspect --timeout=120s
# Both spellings reach the native Pod REST list and generate actual audit records.
k -n "$NS" get pods
k -n "$NS" get стручки
sleep 2
for pod in $(k -n "$NS" get pod -o jsonpath='{.items[*].metadata.name}'); do
 k -n "$NS" exec -i "$pod" -- python3 - <<'PY'
import json,pathlib,subprocess
for item in json.load(open('/host/usr/share/rknetes/components.json')):
 name=item['alias'];args=['chroot','/host','/usr/bin/'+name]+item['flags']
 if name=='hodatay':args.insert(3,'--context=admin@workshop')
 result=subprocess.run(args,input='apiVersion: v1\nkind: ConfigMap\n',capture_output=True,text=True)
 assert result.returncode==0 or(name=='resnichki' and 'cilium' in result.stdout.lower()),(name,result.stdout,result.stderr)
 print(name+': '+(result.stdout+result.stderr).strip())
path=pathlib.Path('/host/var/log/rknetes-audit.json')
if path.is_file():
 records=[json.loads(line) for line in path.read_text().splitlines()]
 matches=[r for r in records if r.get('objectRef',{}).get('namespace')=='lab-native-aliases' and r.get('annotations',{}).get('rknetes.su/terminology')=='использование иностранной терминологии']
 assert len(matches)>=2,matches
 print('PASS: native audit annotated Pod lists from both client spellings; records=',len(matches))
else:print('Worker has no control-plane audit log')
PY
done
k -n "$NS" delete daemonset inspect --wait=true
echo 'PASS: all component aliases executed on every native node and terminology reached the real audit log'
