#!/usr/bin/env bash
# Deliberately incompatible research module. Never edit the conformant checkout.
set -euo pipefail
[[ -d /work/src/kubernetes-rknetes/staging/src/k8s.io/apimachinery ]] || exit 2
export GOMAXPROCS=4 GOWORK=off
ROOT=/work/research/sovereign-api
EVIDENCE=/work/evidence/sovereign-api
[[ ! -e "$ROOT" ]] || { echo 'research checkout already exists; preserve it' >&2; exit 2; }
mkdir -p "$ROOT" "$EVIDENCE"
cp -a /work/src/kubernetes-rknetes/staging/src/k8s.io/apimachinery "$ROOT/apimachinery"
python3 - "$ROOT/apimachinery" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
old='k8s.io/apimachinery/pkg/apis/meta/v1'
new='k8s.io/apimachinery/pkg/apis/zapreshchyonnaya-v-rf/v1'
count=0
for p in root.rglob('*.go'):
    s=p.read_text()
    if old in s:
        p.write_text(s.replace(old,new));count+=1
(root/'pkg/apis/zapreshchyonnaya-v-rf').mkdir()
(root/'pkg/apis/meta/v1').rename(root/'pkg/apis/zapreshchyonnaya-v-rf/v1')
print('Changed Go files:',count)
PY
mkdir "$ROOT/consumer"
cat > "$ROOT/consumer/go.mod" <<EOF
module rknetes.su/sovereign-consumer

go 1.26.0

require k8s.io/apimachinery v0.37.1

replace k8s.io/apimachinery => ../apimachinery
EOF
cat > "$ROOT/consumer/main.go" <<'GO'
package main
import (
  "fmt"
  metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)
func main() { fmt.Println(metav1.ObjectMeta{Name:"sovereign"}.Name) }
GO
cd "$ROOT/consumer"
set +e
go build -mod=mod -p 4 . > "$EVIDENCE/old-import.log" 2>&1
code=$?
set -e
printf '%s\n' "$code" > "$EVIDENCE/old-import.exit-code"
[[ "$code" -ne 0 ]]
grep -F 'does not contain package k8s.io/apimachinery/pkg/apis/meta/v1' "$EVIDENCE/old-import.log"
sed -i 's@apis/meta/v1@apis/zapreshchyonnaya-v-rf/v1@' main.go
go build -mod=mod -p 4 -o consumer . > "$EVIDENCE/new-import.log" 2>&1
./consumer | tee "$EVIDENCE/output.txt"
[[ "$(./consumer)" == sovereign ]]
cp main.go go.mod "$EVIDENCE/"
cd "$ROOT/apimachinery"
go test -p 4 ./pkg/apis/zapreshchyonnaya-v-rf/v1 > "$EVIDENCE/package-tests.log" 2>&1
echo 'PASS: renamed package works; an unchanged upstream import fails to build' | tee "$EVIDENCE/result.txt"
