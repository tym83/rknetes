#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../workshop/common.sh"
(cd "$RK_ROOT" && git ls-files -co --exclude-standard -z | COPYFILE_DISABLE=1 tar --null -T - -czf -) |
    builder sh -c 'mkdir -p /work/src/rknetes && tar -xzf - -C /work/src/rknetes'
