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
runtime=$(k -n rknet-system get pods -l app=rknet-controller -o jsonpath='{.items[0].status.containerStatuses[0].imageID}')
[[ "$runtime" == *@sha256:* ]]
snapshot=$(cd /work/out/rknetes && sha256sum rknet-controller rknet-admission watch-office maxlet | sha256sum | cut -d' ' -f1)
dest=/work/out/releases/$snapshot
mkdir -p "$dest"
for name in rknet-controller rknet-admission watch-office maxlet; do
  if [[ -f "$dest/$name" ]]; then cmp "/work/out/rknetes/$name" "$dest/$name"; else cp "/work/out/rknetes/$name" "$dest/$name"; fi
done
python3 /work/src/rknetes/hack/package/chart.py "$ROOT" "http://$FILES:8080/releases/$snapshot" "$runtime"
/work/bin/helm lint "$ROOT/charts/rknetes"
"$PKG" build "$ROOT" --registry "oci://$FILES:5000/rknetes-packages" --plain-http -o /work/package/dist
"$PKG" repo index /work/package/dist --sign-key /work/keys/rknetes-index.key -o /work/out/packages/index.yaml --plain-http-registry "$FILES:5000"
cp /work/keys/rknetes-index.pub /work/out/packages/index.pub
/work/bin/helm package "$ROOT/charts/rknetes" --destination /work/out/packages
printf '%s\n' "$snapshot" > /work/out/packages/binaries.sha256
