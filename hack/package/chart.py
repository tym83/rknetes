#!/usr/bin/env python3
"""Build the actual add-on chart without placing credentials in its archive."""
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[2]
output = pathlib.Path(sys.argv[1])
binary_url, runtime_image = sys.argv[2:4]
assert '@sha256:' in runtime_image
chart = output/'charts/rknetes'
(chart/'templates').mkdir(parents=True, exist_ok=True)
(chart/'crds').mkdir(exist_ok=True)
(chart/'Chart.yaml').write_text('apiVersion: v2\nname: rknetes\nversion: 0.1.0-3\nappVersion: "0.1.0"\ntype: application\ndescription: Scoped RKNetes controllers, admission and authenticated stream gateways\n')
names = ['rknet-controller', 'rknet-admission', 'watch-office', 'maxlet']
checksums = {name: hashlib.sha256((pathlib.Path('/work/out/rknetes')/name).read_bytes()).hexdigest() for name in names}
(chart/'values.yaml').write_text(json.dumps({'binaryURL': binary_url, 'runtimeImage': runtime_image, 'sha256': checksums}, indent=2)+'\n')
manifest = subprocess.check_output([sys.executable, str(root/'hack/stand/render.py')], env={**os.environ, 'RK_BINARY_URL': '{{ .Values.binaryURL }}', 'RK_CA': '{{ $admissionCA }}'})
objects = json.loads(manifest)['items']
for obj in objects:
    if obj['kind'] not in ('Deployment', 'DaemonSet'):
        continue
    spec = obj['spec']['template']['spec']
    for container in spec['initContainers'] + spec['containers']:
        container['image'] = '{{ .Values.runtimeImage }}'
    binary = obj['metadata']['name']
    init = spec['initContainers'][0]
    destination = '/out' if obj['kind'] == 'Deployment' else '/bin/rk'
    init['command'] = ['sh', '-ec',
        'wget -q -O '+destination+'/'+binary+' "$1/'+binary+'"; printf "%s  '+destination+'/'+binary+'\\n" "$2" | sha256sum -c -; chmod 755 '+destination+'/'+binary,
        'download', '{{ .Values.binaryURL }}', '{{ index .Values.sha256 "'+binary+'" }}']
# Helm expressions inside JSON string values must retain literal inner quotes.
body = '\n---\n'.join(json.dumps(obj, ensure_ascii=False) for obj in objects)
body = re.sub(r'{{.*?}}', lambda match: match.group(0).replace('\\"', '"'), body)
header = []
for var, name, dns in [('admission', 'admission-tls', 'rknet-admission.rknet-system.svc'), ('maxlet', 'maxlet-tls', 'maxlet.rknet-system.svc'), ('watch', 'watch-office-tls', 'watch-office.rknet-system.svc')]:
    # Existing serving certificates survive adoption and later upgrades.
    header.append('{{- $'+var+'Secret := lookup "v1" "Secret" "rknet-system" "'+name+'" -}}')
    header.append('{{- $'+var+'Cert := "" -}}{{- $'+var+'Key := "" -}}')
    header.append('{{- if $'+var+'Secret -}}{{- $'+var+'Cert = index $'+var+'Secret.data "tls.crt" -}}{{- $'+var+'Key = index $'+var+'Secret.data "tls.key" -}}{{- else -}}')
    header.append('{{- $generated := genSelfSignedCert "'+dns+'" (list "127.0.0.1") (list "'+dns+'" "'+dns+'.cluster.local") 365 -}}')
    header.append('{{- $'+var+'Cert = $generated.Cert | b64enc -}}{{- $'+var+'Key = $generated.Key | b64enc -}}{{- end -}}')
header.append('{{- $admissionCA := $admissionCert -}}')
secrets = []
for var, name in [('admission', 'admission-tls'), ('maxlet', 'maxlet-tls'), ('watch', 'watch-office-tls')]:
    secrets.append('apiVersion: v1\nkind: Secret\nmetadata:\n  name: '+name+'\n  namespace: rknet-system\ntype: kubernetes.io/tls\ndata:\n  tls.crt: {{ $'+var+'Cert | quote }}\n  tls.key: {{ $'+var+'Key | quote }}\n')
secrets.append('apiVersion: v1\nkind: Namespace\nmetadata:\n  name: sorm\n')
(chart/'templates/runtime.yaml').write_text('\n'.join(header)+'\n'+body+'\n---\n'+'---\n'.join(secrets))
crds = (root/'deploy/crds.yaml').read_text()
(chart/'crds/rknetes.yaml').write_text(crds)
crd_names = [json.loads(document)['metadata']['name'] for document in crds.split('\n---\n') if document.strip()]
assert len(crd_names) == 17
recipe = {'apiVersion': 'kubepkg.dev/v1', 'kind': 'Recipe', 'metadata': {'name': 'kuberoot-rknetes'}, 'spec': {'version': '0.1.0', 'build': 3, 'sources': {'rknetes': {'dir': 'charts/rknetes'}}, 'charts': {'rknetes': {'from': ['rknetes']}}, 'package': {'crds': crd_names, 'variants': [{'name': 'default', 'requires': [{'package': 'coredns', 'version': '~1.14'}], 'components': [{'name': 'rknetes', 'path': 'rknetes', 'install': {'namespace': 'rknet-system', 'releaseName': 'rknetes', 'privileged': True, 'upgradeCRDs': 'CreateReplace'}}]}]}}}
(output/'recipe.yaml').write_text(json.dumps(recipe, indent=2)+'\n')
# The adoption allowlist contains only resources produced by this repository.
adopt = [{'apiVersion': o['apiVersion'], 'kind': o['kind'], 'metadata': o['metadata']} for o in objects]
adopt += [{'apiVersion':'v1', 'kind':'Secret', 'metadata':{'name':name, 'namespace':'rknet-system'}} for name in ('admission-tls', 'maxlet-tls', 'watch-office-tls')]
adopt.append({'apiVersion':'v1','kind':'Namespace','metadata':{'name':'sorm'}})
(output/'adoption.json').write_text(json.dumps({'apiVersion':'v1','kind':'List','items':adopt}))
