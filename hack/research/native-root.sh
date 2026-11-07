#!/usr/bin/env bash
# Source this helper after producing the native SBOM extraction.
export RK_BASE_ROOTFS_SHA=${RK_BASE_ROOTFS_SHA:-$(sha256sum /work/out/amd64/rootfs.squashfs | cut -d' ' -f1)}
[[ "$RK_BASE_ROOTFS_SHA" =~ ^[a-f0-9]{64}$ ]] || return 2
export RK_NATIVE_ROOT=/work/sbom-roots/$RK_BASE_ROOTFS_SHA
[[ -d "$RK_NATIVE_ROOT/usr/bin" ]] || { echo 'Run hack/package/sbom.sh for this native rootfs first' >&2; return 2; }
