#!/usr/bin/env bash
set -euo pipefail
cd /work/src/rknetes
python3 - <<'PY'
import json,pathlib,subprocess,hashlib,os
native=pathlib.Path('/work/sbom-roots/77599664438d1726c761be12c7180a6fa0c9c9b373f3b5632c814dc15b0f0f64/usr/bin');tools=pathlib.Path('/work/import-tools/bin');out=[]
aliases={'prochee':'etcd','gosplan':'kube-scheduler','kru':'kube-controller-manager','uchastkovy':'kubelet','pochta':'kube-proxy','terminal':'containerd','begunok':'runc'}
for alias,name in aliases.items():
 target=tools/alias
 if not target.exists():target.symlink_to(native/name)
for item in json.load(open('hack/import/components.json')):
 name=item['alias'];path=tools/name
 if name in ['eo-server','hodatay','yaml-office']:path=pathlib.Path('/work/out/optional')/name
 if name=='eo-server':path=pathlib.Path('/work/out/rknetes/eo-server')
 if name=='vpered':path=pathlib.Path('/work/import-tools/go/bin/go')
 if name=='otechestvennoe-yadro':continue
 env={**os.environ,'HODATAY_KUBECTL':'/work/out/rknetes/hodatay-upstream'}
 result=subprocess.run([str(path)]+item['flags'],input='apiVersion: v1\nkind: ConfigMap\n',text=True,capture_output=True,env=env)
 # Cilium also reports that the host lacks a running agent; client version is real.
 assert result.returncode==0 or(name=='resnichki' and 'cilium' in result.stdout.lower()),(item,result.stdout,result.stderr)
 text=result.stdout+result.stderr;print(name+': '+text.strip());out.append({**item,'sha256':hashlib.file_digest(path.open('rb'),'sha256').hexdigest(),'output':text,'exitCode':result.returncode})
pathlib.Path('/work/evidence/import-tools/aliases.json').write_text(json.dumps(out,indent=2)+'\n')
PY
