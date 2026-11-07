#!/usr/bin/env bash
# Explicitly remove disposable lab namespaces after saving test evidence.
set -euo pipefail
source "$(dirname "$0")/common.sh"
[[ $# -gt 0 ]] || { echo 'supply explicit lab namespace names' >&2; exit 2; }
for ns in "$@"; do
  [[ "$ns" == lab-* ]] || exit 2
  [[ "$(k get ns "$ns" -o jsonpath='{.metadata.labels.rknetes\.su/lab}')" == true ]] || exit 2
  if k -n "$ns" get pod ipam-helper >/dev/null 2>&1; then
    k -n "$ns" exec ipam-helper -- sh -c 'test ! -s /tmp/rknetes-ipam-reservations'
  fi
  # Stop reconciliation before removing the deliberately permanent finalizer.
  k label namespace "$ns" rknetes.su/lab=false --overwrite
  k -n "$ns" get pods -o json | python3 -c '
import json,sys
for p in json.load(sys.stdin)["items"]:
    f=p["metadata"].get("finalizers",[])
    if "rknetes.su/forever" in f:
        print(p["metadata"]["name"]+"\t"+json.dumps({"metadata":{"finalizers":[x for x in f if x!="rknetes.su/forever"]}}))
' | while IFS=$'\t' read -r pod patch; do
    k -n "$ns" patch pod "$pod" --type merge -p "$patch"
  done
  k delete namespace "$ns" --wait=false
done
for ns in "$@"; do k wait --for=delete namespace/"$ns" --timeout=180s; done
for pv in pigeon-source pigeon-destination; do
  if [[ "$(k get pv "$pv" -o jsonpath='{.metadata.labels.rknetes\.su/managed}' 2>/dev/null || true)" == true ]]; then
    k delete pv "$pv" --wait=true
  fi
done
k delete clusterrolebinding reestr-self-controller --ignore-not-found
