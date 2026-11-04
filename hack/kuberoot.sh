#!/usr/bin/env bash
# Stage the base in a private checkout; all compilation runs in the tenant.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=${KUBEROOT_SRC:-$ROOT/../kuberoot}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git -C "$SRC" archive "${KUBEROOT_REF:-HEAD}" | tar -xf - -C "$work"
mkdir -p "$work/distros/rknetes/addons"
cp -R "$work/distros/edge/." "$work/distros/rknetes/"
python3 "$ROOT/distro/kuberoot/rknetes/profile.py" "$work/distros/edge/profile.yaml" > "$work/distros/rknetes/profile.yaml"
# The edge meta package selects another CNI; RKNetes installs Cilium explicitly.
rm -f "$work/distros/rknetes/addons/20-edge.yaml"
git -C "$work" init -q
export KUBEROOT_NS=tenant-rknetes KUBE_CONTEXT=admin@workshop KUBEROOT_DISTRO=rknetes
exec_cmd=("$work/hack/hetzner.sh" "$@")
"${exec_cmd[@]}"
