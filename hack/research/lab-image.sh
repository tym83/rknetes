#!/usr/bin/env bash
# Build the isolated protocol/runtime fixture image entirely in the tenant.
set -euo pipefail
[[ -d /work/src/rknetes ]] || exit 2
export PATH=/work/bin:$PATH
export DEBIAN_FRONTEND=noninteractive
apt-get -qq update
apt-get -qq install --no-install-recommends -y openvpn wireguard-tools iodine ptunnel-ng iproute2 net-tools openssl python3 curl >/work/tmp/tunnel-packages.log
mkdir -p /work/out/tools /work/evidence/tunnel-build
if [[ ! -x /work/bin/crane ]]; then GOBIN=/work/bin GOMAXPROCS=4 go install -p 4 github.com/google/go-containerregistry/cmd/crane@v0.20.3; fi
GOBIN=/work/tmp/xray-build GOMAXPROCS=4 go install -p 4 github.com/xtls/xray-core/main@v1.250516.0
cp /work/tmp/xray-build/main /work/out/tools/xray
GOBIN=/work/tmp/wg-build GOMAXPROCS=4 go install -p 4 golang.zx2c4.com/wireguard@v0.0.0-20261024220952-b3bc704ef0ee
cp /work/tmp/wg-build/wireguard /work/out/tools/wireguard-go
for name in xray wireguard-go; do go version -m "/work/out/tools/$name" > "/work/evidence/tunnel-build/$name.build-info.txt"; done
dpkg-query -W -f='${Package}\t${Version}\t${source:Package}\t${source:Version}\n' openvpn wireguard-tools iodine ptunnel-ng iproute2 net-tools openssl python3 curl > /work/evidence/tunnel-build/debian-packages.tsv
source /work/src/rknetes/hack/research/native-root.sh
python3 - <<'PY'
from pathlib import Path
import os,re,shutil,subprocess,tarfile
root=Path('/work/lab-image/root')
if root.exists():shutil.rmtree(root)
root.mkdir(parents=True)
def copy(path,destination=None):
 p=Path(path);dest=root/(destination or str(p)).lstrip('/')
 dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p.resolve(),dest)
def binary(path,destination=None):
 copy(path,destination)
 r=subprocess.run(['ldd',path],text=True,capture_output=True)
 for lib in re.findall(r'(/[^\s()]+)',r.stdout):
  if Path(lib).is_file():copy(lib)
for name in ['openvpn','wg','iodine','iodined','ptunnel-ng','ip','ifconfig','route','openssl','python3','curl']:
 binary(shutil.which(name))
shutil.copytree('/usr/lib/python3.11',root/'usr/lib/python3.11',dirs_exist_ok=True)
for extension in Path('/usr/lib/python3.11').rglob('*.so'):binary(str(extension))
for name in ['xray','wireguard-go']:copy('/work/out/tools/'+name,'/usr/local/bin/'+name)
native=Path('/work/sbom-roots')/os.environ['RK_BASE_ROOTFS_SHA']/'usr/bin'
for name in ['containerd','ctr','runc','etcd','etcdutl']:binary(str(native/name),'/usr/local/bin/'+name)
copy('/work/bin/helm','/usr/local/bin/helm')
copy('/work/bin/crane','/usr/local/bin/crane')
for name in ['openvpn','wireguard-tools','iodine','ptunnel-ng','iproute2','net-tools','openssl','python3','curl']:
 p=Path('/usr/share/doc')/name/'copyright'
 if p.exists():copy(str(p))
for module,target in [('github.com/xtls/xray-core@v1.250516.0','xray'),('golang.zx2c4.com/wireguard@v0.0.0-20261024220952-b3bc704ef0ee','wireguard-go')]:
 p=Path('/work/go/pkg/mod')/module/'LICENSE'
 if p.exists():copy(str(p),'/usr/share/doc/'+target+'/LICENSE')
with tarfile.open('/work/lab-image/tools.tar','w') as out:
 for p in sorted(root.iterdir()):out.add(p,arcname=p.name,recursive=True)
PY
base=sha256:c67e92c8099ba22853ab4cfda7cfb494d253d6012ca82dee98ba8976772af018
printf 'debian:bookworm-slim@%s\n' "$base" > /work/evidence/tunnel-build/base-image.txt
tag=10.244.8.11:5000/rknetes-lab-tools:1
crane append --platform linux/amd64 --insecure -b "debian:bookworm-slim@$base" -f /work/lab-image/tools.tar -t "$tag" >/work/evidence/tunnel-build/push.log 2>&1
digest=$(crane digest --insecure "$tag")
printf '10.244.8.11:5000/rknetes-lab-tools@%s\n' "$digest" > /work/out/tools/lab-image.ref
crane pull --insecure --platform linux/amd64 --format tarball "$tag" /work/out/tools/lab-image.tar
sha256sum /work/out/tools/lab-image.tar > /work/evidence/tunnel-build/image-archive.sha256
cp /work/out/tools/lab-image.ref /work/evidence/tunnel-build/
echo 'PASS: lab protocol/runtime image built and stored only in the private tenant registry'
