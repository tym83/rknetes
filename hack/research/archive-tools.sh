#!/usr/bin/env bash
# Build a private tools layer for the disposable, bounded control plane.
set -euo pipefail
cd /work/src/rknetes
mkdir -p /work/archive-tools/root /work/out/tools
python3 - <<'PY'
import pathlib,re,shutil,subprocess,tarfile
root=pathlib.Path('/work/archive-tools/root')
def copy(p,target=None):
 dest=root/(target or str(p)).lstrip('/');dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(pathlib.Path(p).resolve(),dest)
for name in ['losetup','mkfs.ext4']:
 p=shutil.which(name);copy(p,'/usr/local/bin/'+name)
 for lib in re.findall(r'(/[^\s()]+)',subprocess.run(['ldd',p],text=True,capture_output=True).stdout):
  if pathlib.Path(lib).is_file():copy(lib)
copy('/work/sbom-roots/77599664438d1726c761be12c7180a6fa0c9c9b373f3b5632c814dc15b0f0f64/usr/bin/eo-server','/usr/local/bin/eo-server')
with tarfile.open('/work/out/tools/archive-tools.tar.gz','w:gz') as out:
 for p in root.iterdir():out.add(p,arcname=p.name)
PY
sha256sum /work/out/tools/archive-tools.tar.gz
