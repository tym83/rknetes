#!/usr/bin/env bash
# Run the complete measured tour and long-duration proofs on one signed release.
set -euo pipefail
cd /work/src/rknetes
source hack/e2e/common.sh
RUN=${1:?unique demo evidence name}
[[ "$RUN" =~ ^[a-z0-9-]+$ ]] || exit 2
OUT=/work/evidence/$RUN
mkdir "$OUT"
date -u +%FT%TZ > "$OUT/started.txt"
sha256sum /work/out/rknetes/* > "$OUT/runtime.sha256"
k get nodes -o wide > "$OUT/nodes.txt"
k get package.kubepkg.dev/kuberoot-rknetes -o yaml > "$OUT/package.yaml"
# Optional experiments must exercise exactly the shipped release commands.
for source in cmd/*/main.go; do
 name=${source%/main.go}; name=${name##*/}
 cmp "/work/out/rknetes/$name" "/work/out/optional/$name"
done
result=0
groups=()
pids=()
run() {
 local group=$1; shift
 groups+=("$RUN-$group")
 bash hack/e2e/run.sh "$RUN-$group" "$@" || result=1
}
background() {
 local group=$1; shift
 groups+=("$RUN-$group")
 bash hack/e2e/run.sh "$RUN-$group" "$@" > "$OUT/$group-driver.log" 2>&1 &
 pids+=("$!")
}
echo 'RKNetes: Сбоев не зафиксировано. Every scene below executes actual stand assertions.'
# Complete node taints and bounded IPAM reservation before long-lived clients.
run preparation 08-import 08-native-aliases 06-max-priority \
  04-schedule 12-cooling 12-roaming 01-reestr 11-blogger
[[ "$result" == 0 ]] || exit "$result"
background escalation-soak 01-escalation-soak
background measurements 05-measurements
background watch-scale 11-blogger-scale
run registry 01-escalation 01-telegram-cycle 01-self-block 02-throttle
run bytes 03-sovereign-16k 03-byte-policy 03-boundaries 03-api-streams
run whitelist 04-whitelist 04-observe 04-ephemeral 04-werewolf 04-capacity 04-dependency-graph
run tunnels 05-pigeon 05-pigeon-interface 05-tunnel-ladder 05-compliant
run calls 06-calls 06-max 06-max-enrollment
run import 07-origin 07-origin-resolution 08-goshran 08-goshran-country 08-artifact-chain \
  08-native-pulls 08-reinvocation 08-module-mirror 08-toolchain-mirror
run storage 09-escrow-forever 09-key-refusal 09-first-write
run regulation 10-drill 10-national-dns 10-presentation 10-ponyatno-kto 11-erid \
  11-watch-resources 17-agencies 17-agency-timeout
# This one application crosses native pulls, real tunnels, self-block and
# physical ENOSPC. It includes 09-payload-archive and performs repairs via MAX.
run composed 18-composed-shop
for pid in "${pids[@]}"; do wait "$pid" || result=1; done
python3 - "$OUT" "${groups[@]}" <<'REPORT'
import json,pathlib,sys
out=pathlib.Path(sys.argv[1]);checks=[]
for name in sys.argv[2:]:
 root=out.parent/name
 for path in sorted(root.glob('*.exit-code')):
  checks.append({'group':name,'test':path.name.removesuffix('.exit-code'),'exitCode':int(path.read_text())})
report={'checks':len(checks),'passed':sum(c['exitCode']==0 for c in checks),'failed':sum(c['exitCode']!=0 for c in checks),'nestedProof':'18-composed-shop executes 09-payload-archive with real MAX recovery','results':checks}
(out/'summary.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k!='results'},indent=2))
REPORT
date -u +%FT%TZ > "$OUT/finished.txt"
printf '%s\n' "$result" > "$OUT/exit-code"
exit "$result"
