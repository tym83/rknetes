#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-archive
new_namespace "$NS"
fixture rutracker
k -n "$NS" apply -f - <<'YAML'
apiVersion: v1
kind: Secret
metadata: {name: tls}
type: kubernetes.io/tls
stringData: {tls.crt: lab-certificate, tls.key: lab-key}
---
apiVersion: rknetes.su/v1alpha1
kind: ReestrEntry
metadata: {name: rutracker}
spec: {podName: rutracker, forever: true}
YAML
UID_TLS=$(k -n "$NS" get secret tls -o jsonpath='{.metadata.uid}')
wait_until k -n sorm get secret "escrow-$UID_TLS"
[[ "$(k -n sorm get secret "escrow-$UID_TLS" -o jsonpath='{.data.tls\.key}')" == "$(k -n "$NS" get secret tls -o jsonpath='{.data.tls\.key}')" ]]
k -n "$NS" wait --for=condition=Applied reestrentry/rutracker --timeout=60s
k -n "$NS" delete pod rutracker --wait=false
[[ -n "$(k -n "$NS" get pod rutracker -o jsonpath='{.metadata.deletionTimestamp}')" ]]
[[ "$(k -n "$NS" get pod rutracker -o jsonpath='{.metadata.finalizers[0]}')" == rknetes.su/forever ]]
echo 'PASS: TLS escrow contains exact bytes; finalizer retains deleted Pod'
