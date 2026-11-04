#!/usr/bin/env bash
# Adopt only this repository's own installation into the signed package.
set -euo pipefail
source /work/src/rknetes/hack/e2e/common.sh
FILES=${1:?private builder Pod IP required}
[[ "$FILES" == 10.244.* ]] || exit 2
ROOT=/work/package/rknetes
python3 - "$ROOT/adoption.json" <<'PY'
import json, os, subprocess, sys
objects = json.load(open(sys.argv[1]))['items']
base = ['kubectl', '--context', 'admin@workshop', '--kubeconfig', os.environ['KUBECONFIG']]
for obj in objects:
    meta = obj['metadata']
    args = base + (['-n', meta['namespace']] if meta.get('namespace') else [])
    resource = obj['kind']+'/'+meta['name']
    current = json.loads(subprocess.check_output(args+['get', resource, '-o', 'json']))
    annotations = current['metadata'].get('annotations', {})
    owner = annotations.get('meta.helm.sh/release-name')
    if owner and owner != 'rknetes':
        raise SystemExit('Refusing to adopt another Helm release: '+resource)
    patch = {'metadata': {'labels': {'app.kubernetes.io/managed-by': 'Helm'}, 'annotations': {'meta.helm.sh/release-name': 'rknetes', 'meta.helm.sh/release-namespace': 'rknet-system'}}}
    subprocess.run(args+['patch', resource, '--type=merge', '-p', json.dumps(patch)], check=True)
PY
# kubepkg 1.3.0 uses Helm 4 SSA on first install. Transfer the CRD fields
# explicitly, then let Helm 3 perform the one-time migration of our manifests.
k apply --server-side --force-conflicts --field-manager=kubepkg-operator -f /work/src/rknetes/deploy/crds.yaml
if ! /work/bin/helm status rknetes --namespace rknet-system --kube-context admin@workshop >/dev/null 2>&1; then
  /work/bin/helm install rknetes "$ROOT/charts/rknetes" --namespace rknet-system --kube-context admin@workshop --skip-crds --wait --timeout 3m
fi
pkg() { env -u KUBERNETES_SERVICE_HOST -u KUBERNETES_SERVICE_PORT /work/out/amd64/kubepkg "$@"; }
pkg repo add rknetes "http://$FILES:8080/packages/index.yaml" --public-key /work/keys/rknetes-index.pub --plain-http-registry "$FILES:5000" --interval 30s --priority 100
k wait --for=condition=Ready repository.kubepkg.dev/rknetes --timeout=180s
pkg install kuberoot-rknetes --yes
k wait --for=condition=Ready package.kubepkg.dev/kuberoot-rknetes --timeout=300s
k -n rknet-system rollout status deployment/rknet-controller --timeout=180s
k -n rknet-system rollout status deployment/rknet-admission --timeout=180s
k -n rknet-system rollout status deployment/watch-office --timeout=180s
k -n rknet-system rollout status daemonset/maxlet --timeout=180s
mkdir -p /work/evidence/package
k get repository.kubepkg.dev/rknetes package.kubepkg.dev/kuberoot-rknetes -o yaml > /work/evidence/package/installed.yaml
sha256sum /work/out/packages/index.yaml /work/out/packages/rknetes-0.1.0.tgz > /work/evidence/package/sha256.txt
