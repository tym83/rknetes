#!/usr/bin/env bash
# Hydrophone launcher compatibility fix; the upstream test image is unchanged.
set -euo pipefail
cd /work/src/rknetes
src=$(go mod download -json sigs.k8s.io/hydrophone@v0.5.0 | python3 -c 'import json,sys;print(json.load(sys.stdin)["Dir"])')
work=/work/src/hydrophone-rknetes
mkdir -p "$work"
cp -a "$src/." "$work/"
chmod -R u+w "$work"
python3 - "$work/pkg/service/init.go" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text()
a='Name:  "E2E_PARALLEL",\n\t\t\t\t\t\t\tValue: fmt.Sprintf("%d", viper.Get("parallel"))'
b='Name:  "E2E_EXTRA_GINKGO_ARGS",\n\t\t\t\t\t\t\tValue: fmt.Sprintf("--procs=%d", viper.Get("parallel"))'
assert s.count(a)==1
p.write_text(s.replace(a,b))
PY
cd "$work"
GOMAXPROCS=4 go build -p 4 -trimpath -o /work/bin/hydrophone-rknetes .
