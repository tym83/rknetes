#!/usr/bin/env bash
# Publish an immutable private snapshot and its hashes to the nested controllers.
set -euo pipefail
source "$(dirname "$0")/../e2e/common.sh"
cd /work/out/optional
names=(pigeon drill-trigger)
snapshot=$(sha256sum "${names[@]}" | sha256sum | cut -d' ' -f1)
destination=/work/out/releases/$snapshot
mkdir -p "$destination"
args=(--from-literal="url=http://10.244.8.11:8080/releases/$snapshot" --from-literal="image=$(cat /work/out/tools/lab-image.ref)")
for name in "${names[@]}"; do
 if [[ -f "$destination/$name" ]]; then cmp "$name" "$destination/$name"; else cp "$name" "$destination/$name"; fi
 args+=(--from-literal="sha256.$name=$(sha256sum "$name" | cut -d' ' -f1)")
done
k -n rknet-system create configmap runtime-artifacts "${args[@]}" --dry-run=client -o yaml | k apply -f -
k -n rknet-system label configmap runtime-artifacts rknetes.su/managed=true --overwrite
