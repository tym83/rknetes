#!/usr/bin/env bash
# Build and sign artifacts only inside the tenant builder's private registry.
set -euo pipefail
source /work/src/rknetes/hack/e2e/common.sh
FILES=${1:?private builder Pod IP required}
[[ "$FILES" == 10.244.* ]] || exit 2
PKG=/work/out/amd64/kubepkg
ROOT=/work/package/rknetes
mkdir -p /work/keys /work/out/packages /work/package/dist
if [[ ! -f /work/keys/rknetes-index.key ]]; then "$PKG" repo keygen /work/keys/rknetes-index; fi
# Pinned in the repository. Reading it back from a running Pod is unreliable: the
# node's imageID names whichever repository it last saw with that digest, and after
# the import-substitution tests that is a lab loopback name nobody else can pull.
runtime=$(cat /work/src/rknetes/hack/package/runtime-image.ref)
[[ "$runtime" == *@sha256:* ]]
names=()
for source in /work/src/rknetes/cmd/*/main.go; do name=${source%/main.go}; names+=("${name##*/}"); done
names+=(tspu.o)
snapshot=$(cd /work/out/rknetes && sha256sum "${names[@]}" | sha256sum | cut -d' ' -f1)
dest=/work/out/releases/$snapshot
mkdir -p "$dest"
for name in "${names[@]}"; do
  if [[ -f "$dest/$name" ]]; then cmp "/work/out/rknetes/$name" "$dest/$name"; else cp "/work/out/rknetes/$name" "$dest/$name"; fi
done
python3 /work/src/rknetes/hack/package/chart.py "$ROOT" "http://$FILES:8080/releases/$snapshot" "$runtime"
/work/bin/helm lint "$ROOT/charts/rknetes"
"$PKG" build "$ROOT" --registry "oci://$FILES:5000/rknetes-packages" --plain-http -o /work/package/dist
"$PKG" repo index /work/package/dist --sign-key /work/keys/rknetes-index.key -o /work/out/packages/index.yaml --plain-http-registry "$FILES:5000"
cp /work/keys/rknetes-index.pub /work/out/packages/index.pub
/work/bin/helm package "$ROOT/charts/rknetes" --destination /work/out/packages
printf '%s\n' "$snapshot" > /work/out/packages/binaries.sha256
