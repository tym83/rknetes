#!/usr/bin/env bash
# Inventory public build outputs. Never traverse private /work credential trees.
set -euo pipefail
REV=${1:?exact RKNetes component source commit required}
[[ "$REV" =~ ^[a-f0-9]{40}$ ]] || exit 2
OVERLAY=${2:-$REV}
[[ "$OVERLAY" =~ ^[a-f0-9]{40}$ ]] || exit 2
mkdir -p /work/out/provenance
cd /work/src/rknetes
GOMAXPROCS=4 go list -m -json all > /work/out/provenance/rknetes-go-modules.json
cp go.sum /work/out/provenance/rknetes-go.sum
find distro hack/import -type f ! -path '*/__pycache__/*' -print0 | sort -z | xargs -0 sha256sum > /work/out/provenance/overlay-files.sha256
cp /work/out/amd64/kernel.config /work/out/provenance/linux.config
cp /work/src/kuberoot/kernel/VERSION /work/out/provenance/linux-version.txt
cp /work/src/kuberoot/kernel/DRBD_VERSION /work/out/provenance/drbd-version.txt
cd /work/src/kubernetes-rknetes
git rev-parse HEAD > /work/out/provenance/kubernetes-upstream-commit.txt
git diff --binary > /work/out/provenance/kubernetes.patch
go version -m /work/out/rknetes/eo-server > /work/out/provenance/eo-server-buildinfo.txt
cd /work/out
sha256sum rknetes/* amd64/rootfs.squashfs amd64/kernel.config amd64/vmlinuz.efi amd64/bundles/kuberoot-0.1.0-dev-amd64.tar > provenance/artifacts.sha256
printf '%s\n' ee4bf243ea9b81e2c94799c2c82df3792ba74c31 > provenance/kuberoot-base-commit.txt
printf '%s\n' "$REV" > provenance/rknetes-components-commit.txt
printf '%s\n' "$OVERLAY" > provenance/rknetes-overlay-commit.txt
printf 'RKNetes component source: %s\nNative/builder equality is verified in binary-comparison.json.\n' "$REV" > provenance/checkpoints.txt
python3 - <<'PY'
from pathlib import Path
import hashlib,json
rootfs=Path('/work/out/amd64/rootfs.squashfs')
sha=hashlib.file_digest(rootfs.open('rb'),'sha256').hexdigest()
root=Path('/work/sbom-roots')/sha
assert root.is_dir(), 'run sbom.sh against this rootfs first'
rows=[]
for path in sorted(Path('/work/out/rknetes').iterdir()):
    native=root/'usr/bin'/path.name
    if not native.is_file():continue
    a=hashlib.file_digest(path.open('rb'),'sha256').hexdigest()
    b=hashlib.file_digest(native.open('rb'),'sha256').hexdigest()
    rows.append({'name':path.name,'builderSHA256':a,'nativeSHA256':b,'equal':a==b})
Path('/work/out/provenance/binary-comparison.json').write_text(json.dumps(rows,indent=2)+'\n')
assert all(x['equal'] for x in rows),rows
print('PASS: all compared native and builder binaries match')
PY
