#!/usr/bin/env bash
# Run in the tenant builder after bootstrap.sh has written the nested marker.
set -euo pipefail
source /work/src/rknetes/hack/e2e/common.sh
[[ "$(k config view --minify -o jsonpath='{.clusters[0].cluster.server}')" != *workshop* ]]
cd /work/src/rknetes
k apply -f deploy/crds.yaml
for name in $(k get crds -o name | grep '\.rknetes\.su$'); do k wait --for=condition=Established "$name" --timeout=60s; done
for name in rknet-system sorm; do
  k create namespace "$name" --dry-run=client -o yaml | k apply -f -
done
k label namespace rknet-system pod-security.kubernetes.io/enforce=privileged --overwrite
mkdir -p /work/tls/rknetes /work/tls/maxlet
if [[ ! -e /work/tls/rknetes/tls.key ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
    -keyout /work/tls/rknetes/tls.key -out /work/tls/rknetes/tls.crt \
    -subj /CN=rknet-admission.rknet-system.svc \
    -addext 'subjectAltName=DNS:rknet-admission.rknet-system.svc,DNS:rknet-admission.rknet-system.svc.cluster.local' >/dev/null 2>&1
fi
k -n rknet-system create secret tls admission-tls --cert=/work/tls/rknetes/tls.crt --key=/work/tls/rknetes/tls.key --dry-run=client -o yaml | k apply -f -
if [[ ! -e /work/tls/maxlet/tls.key ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 30 -keyout /work/tls/maxlet/tls.key -out /work/tls/maxlet/tls.crt -subj /CN=maxlet.rknet-system.svc -addext 'subjectAltName=DNS:maxlet.rknet-system.svc,IP:127.0.0.1' >/dev/null 2>&1
fi
k -n rknet-system create secret tls maxlet-tls --cert=/work/tls/maxlet/tls.crt --key=/work/tls/maxlet/tls.key --dry-run=client -o yaml | k apply -f -
mkdir -p /work/tls/watch
if [[ ! -e /work/tls/watch/tls.key ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 30 -keyout /work/tls/watch/tls.key -out /work/tls/watch/tls.crt -subj /CN=watch-office.rknet-system.svc -addext 'subjectAltName=DNS:watch-office.rknet-system.svc,IP:127.0.0.1' >/dev/null 2>&1
fi
k -n rknet-system create secret tls watch-office-tls --cert=/work/tls/watch/tls.crt --key=/work/tls/watch/tls.key --dry-run=client -o yaml | k apply -f -
export RK_BINARY_URL=${RK_BINARY_URL:?builder Pod IP URL required}
export RK_CA=$(base64 -w0 /work/tls/rknetes/tls.crt)
python3 hack/stand/render.py | k apply -f -
k -n rknet-system rollout status deployment/rknet-controller --timeout=180s
k -n rknet-system rollout status deployment/rknet-admission --timeout=180s

k -n rknet-system rollout status deployment/watch-office --timeout=180s
