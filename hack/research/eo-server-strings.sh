#!/usr/bin/env bash
# Count "kubernetes" in the domestic Единое окно and in the foreign kube-apiserver of the
# same version, downloaded from the official release and verified by its published hash.
set -euo pipefail
domestic=${1:-/work/out/rknetes/eo-server}
version=${2:-v1.37.1}
work=$(mktemp -d /work/tmp/eo-strings.XXXXXX)
trap 'rm -rf "$work"' EXIT
base=https://dl.k8s.io/release/$version/bin/linux/amd64
curl -fsSL -o "$work/kube-apiserver" "$base/kube-apiserver"
echo "$(curl -fsSL "$base/kube-apiserver.sha256")  $work/kube-apiserver" | sha256sum -c - >/dev/null
count() { strings "$1" | grep -c -i kubernetes; }
d=$(count "$domestic"); f=$(count "$work/kube-apiserver")
echo "\$ strings eo-server | grep -c -i kubernetes"
echo "$d"
echo "\$ strings kube-apiserver | grep -c -i kubernetes   # foreign, $version"
echo "$f"
echo "Кормчий: $(strings "$domestic" | grep -c 'Кормчий' || true)"
python3 - "$d" "$f" <<'PY'
import sys
d, f = map(int, sys.argv[1:])
print(f"domestic/foreign = {d/f:.4f}; difference {d-f:+d}")
PY
