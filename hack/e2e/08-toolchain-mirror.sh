#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
RK_GO_MIRROR=/work/out/optional/go-mirror bash hack/import/compiler.sh
