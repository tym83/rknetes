#!/usr/bin/env bash
# Stage the base in a private checkout; all compilation runs in the tenant.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=${KUBEROOT_SRC:-$ROOT/../kuberoot}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git -C "$SRC" archive "${KUBEROOT_REF:-ee4bf243ea9b81e2c94799c2c82df3792ba74c31}" | tar -xf - -C "$work"
mkdir -p "$work/distros/rknetes/addons"
cp -R "$work/distros/edge/." "$work/distros/rknetes/"
python3 "$ROOT/distro/kuberoot/rknetes/profile.py" "$work/distros/edge/profile.yaml" > "$work/distros/rknetes/profile.yaml"
cp "$ROOT/distro/kuberoot/rknetes/extras.sh" "$work/distros/rknetes/extras.sh"
git -C "$work" init -q
export KUBEROOT_NS=tenant-rknetes KUBE_CONTEXT=admin@workshop KUBEROOT_DISTRO=rknetes
exec_cmd=("$work/hack/hetzner.sh" "$@")
"${exec_cmd[@]}"
