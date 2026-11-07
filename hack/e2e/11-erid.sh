#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-erid
new_namespace "$NS"
k -n "$NS" apply -f - <<'YAML'
apiVersion: rknetes.su/v1alpha1
kind: AdvertisingPolicy
metadata: {name: advertising}
spec: {enabled: true}
YAML
if k -n "$NS" create -f - > /tmp/rknet-erid.out 2>&1 <<YAML
apiVersion: v1
kind: Event
metadata: {name: unmarked}
involvedObject: {apiVersion: v1, kind: Pod, namespace: $NS, name: nginx}
reason: Pulled
message: Successfully pulled image nginx
type: Normal
YAML
then exit 1; fi
grep -q 'требуется erid' /tmp/rknet-erid.out
k -n "$NS" create -f - <<YAML
apiVersion: v1
kind: Event
metadata: {name: marked, annotations: {rknetes.su/erid: lab-123}}
involvedObject: {apiVersion: v1, kind: Pod, namespace: $NS, name: nginx}
reason: Pulled
message: Successfully pulled image nginx
type: Normal
YAML
echo 'PASS: successful Event requires erid'
