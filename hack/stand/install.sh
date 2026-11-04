#!/usr/bin/env bash
# Run in the tenant builder after bootstrap.sh has written the nested marker.
set -euo pipefail
source /work/src/rknetes/hack/e2e/common.sh
[[ "$(k config view --minify -o jsonpath='{.clusters[0].cluster.server}')" != *workshop* ]]
cd /work/src/rknetes
TLS_DIR=${RK_TLS_DIR:-/work/tls}
case "$TLS_DIR" in /work/tls|/work/cleanroom/tls) ;; *) exit 2 ;; esac
k apply -f deploy/crds.yaml
for name in $(k get crds -o name | grep '\.rknetes\.su$'); do k wait --for=condition=Established "$name" --timeout=60s; done
for name in rknet-system sorm; do
  k create namespace "$name" --dry-run=client -o yaml | k apply -f -
done
k label namespace rknet-system pod-security.kubernetes.io/enforce=privileged --overwrite
mkdir -p $TLS_DIR/rknetes $TLS_DIR/maxlet
if [[ ! -e $TLS_DIR/rknetes/tls.key ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
    -keyout $TLS_DIR/rknetes/tls.key -out $TLS_DIR/rknetes/tls.crt \
    -subj /CN=rknet-admission.rknet-system.svc \
    -addext 'subjectAltName=DNS:rknet-admission.rknet-system.svc,DNS:rknet-admission.rknet-system.svc.cluster.local' >/dev/null 2>&1
fi
k -n rknet-system create secret tls admission-tls --cert=$TLS_DIR/rknetes/tls.crt --key=$TLS_DIR/rknetes/tls.key --dry-run=client -o yaml | k apply -f -
if [[ ! -e $TLS_DIR/maxlet/tls.key ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 30 -keyout $TLS_DIR/maxlet/tls.key -out $TLS_DIR/maxlet/tls.crt -subj /CN=maxlet.rknet-system.svc -addext 'subjectAltName=DNS:maxlet.rknet-system.svc,IP:127.0.0.1' >/dev/null 2>&1
fi
k -n rknet-system create secret tls maxlet-tls --cert=$TLS_DIR/maxlet/tls.crt --key=$TLS_DIR/maxlet/tls.key --dry-run=client -o yaml | k apply -f -
mkdir -p $TLS_DIR/watch
if [[ ! -e $TLS_DIR/watch/tls.key ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 30 -keyout $TLS_DIR/watch/tls.key -out $TLS_DIR/watch/tls.crt -subj /CN=watch-office.rknet-system.svc -addext 'subjectAltName=DNS:watch-office.rknet-system.svc,IP:127.0.0.1' >/dev/null 2>&1
fi
k -n rknet-system create secret tls watch-office-tls --cert=$TLS_DIR/watch/tls.crt --key=$TLS_DIR/watch/tls.key --dry-run=client -o yaml | k apply -f -
export RK_BINARY_URL=${RK_BINARY_URL:?builder Pod IP URL required}
export RK_CA=$(base64 -w0 $TLS_DIR/rknetes/tls.crt)
python3 hack/stand/render.py | k apply -f -
k -n rknet-system rollout status deployment/rknet-controller --timeout=180s
k -n rknet-system rollout status deployment/rknet-admission --timeout=180s

k -n rknet-system rollout status deployment/watch-office --timeout=180s
