#!/usr/bin/env bash
# Scan only distributable build outputs, never /work/kube, keys, tls or trust.
set -euo pipefail
export PATH=/work/bin:$PATH
version=1.55.0
archive=/work/tmp/syft_${version}_linux_amd64.tar.gz
if [[ ! -x /work/bin/syft ]]; then
  curl --fail --location --max-time 180 "https://github.com/anchore/syft/releases/download/v$version/syft_${version}_linux_amd64.tar.gz" -o "$archive"
  printf '%s  %s\n' bb65249542db5fedeeb4d3f9b018b75e7264dbfbbb10486f044581a92f90490d "$archive" | sha256sum -c -
  tar -xzf "$archive" -C /work/bin syft
fi
root=/work/sbom-rootfs
mkdir -p /work/out/sbom
if ! command -v unsquashfs >/dev/null; then
  apt-get update -qq
  apt-get install -y -qq squashfs-tools
fi
if [[ ! -d "$root" ]]; then unsquashfs -no-progress -processors 4 -d "$root" /work/out/amd64/rootfs.squashfs; fi
SYFT_CHECK_FOR_APP_UPDATE=false SYFT_GOLANG_SEARCH_LOCAL_MOD_CACHE_LICENSES=true \
  SYFT_GOLANG_SEARCH_LOCAL_VENDOR_LICENSES=true SYFT_GOLANG_LOCAL_VENDOR_DIR=/work/src/kubernetes-rknetes/vendor \
  syft scan "dir:$root" --source-name rknetes --source-version 0.1.0-dev -o spdx-json=/work/out/sbom/native.spdx.json -o syft-json=/work/out/sbom/native.syft.json
sha256sum /work/out/amd64/rootfs.squashfs /work/out/amd64/bundles/kuberoot-0.1.0-dev-amd64.tar > /work/out/sbom/subjects.sha256
python3 - <<'PY'
from collections import Counter
from pathlib import Path
import csv, json
root=Path('/work/out/sbom')
sbom=json.loads((root/'native.syft.json').read_text())
with (root/'components.csv').open('w') as handle:
    out=csv.writer(handle)
    out.writerow(['name','version','type','declared_licenses','evidence_paths'])
    for p in sorted(sbom['artifacts'], key=lambda p:(p['name'],p['version'])):
        licenses=';'.join(x.get('spdxExpression') or x.get('value','') for x in p.get('licenses',[])) or 'NOASSERTION'
        out.writerow([p['name'],p['version'],p['type'],licenses,';'.join(x.get('path','') for x in p.get('locations',[]))])
summary={'packageInstances':len(sbom['artifacts']), 'distinctNameVersionType':len({(p['name'],p['version'],p['type']) for p in sbom['artifacts']}), 'types':dict(Counter(p['type'] for p in sbom['artifacts'])), 'instancesWithoutLicense':sum(not p.get('licenses') for p in sbom['artifacts']), 'scope':'immutable native root filesystem; scanner findings, not a completed legal review'}
(root/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2))
PY
