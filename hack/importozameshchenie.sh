#!/usr/bin/env bash
# Run only in the tenant builder against a dedicated upstream checkout.
# Preserve all copyright, LICENSE and NOTICE files and version metadata.
set -euo pipefail
src=${1:?dedicated upstream Kubernetes checkout required}
[[ "$src" == /work/src/kubernetes-rknetes ]] || { echo 'requires the dedicated builder checkout' >&2; exit 1; }
[[ -f "$src/go.mod" ]] || exit 1
cd "$src"
# This is intentionally a literal sed-based rebranding, not a new API implementation.
version=staging/src/k8s.io/kubectl/pkg/cmd/version/version.go
sed -i -e 's/Client Version:/Клиент: Кормчий-Ходатай/g' -e 's/Server Version:/Сервер: Кормчий-Единое окно/g' "$version"
# Extend upstream discovery, so an unmodified kubectl also accepts the alias.
python3 - <<'PY'
from pathlib import Path
p=Path('pkg/registry/core/pod/storage/storage.go')
s=p.read_text()
if '"стручки"' not in s:
    old='return []string{"po"}'
    assert old in s, 'upstream Pod ShortNames changed'
    s=s.replace(old, 'return []string{"po", "стручки"}', 1)
p.write_text(s)
PY
mkdir -p /work/out/rknetes
# Upstream's normal build stamps both version packages. Keep the true commit
# and mark our modified tree dirty; never advertise a fabricated clean tree.
commit=$(git rev-parse HEAD)
build_date=$(git show -s --format=%cI HEAD)
ldflags=""
for package in k8s.io/client-go/pkg/version k8s.io/component-base/version; do
  ldflags+=" -X $package.gitVersion=v1.37.1 -X $package.gitMajor=1 -X $package.gitMinor=37"
  ldflags+=" -X $package.gitCommit=$commit -X $package.gitTreeState=dirty -X $package.buildDate=$build_date"
done
GOFLAGS=-mod=vendor GOMAXPROCS=4 CGO_ENABLED=0 go build -p 4 -trimpath -ldflags "$ldflags" -o /work/out/rknetes/hodatay-upstream ./cmd/kubectl
GOFLAGS=-mod=vendor GOMAXPROCS=4 CGO_ENABLED=0 go build -p 4 -trimpath -ldflags "$ldflags" -o /work/out/rknetes/eo-server ./cmd/kube-apiserver
git diff --exit-code -- '**/LICENSE*' '**/NOTICE*'
git diff --stat > /work/out/rknetes/importozameshchenie.diffstat
