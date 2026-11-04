#!/usr/bin/env bash
# A reproducible measured tour. Keep each script's real assertions and evidence.
set -euo pipefail
cd /work/src/rknetes
RUN=${1:?unique demo evidence name}
echo 'RKNetes: Сбоев не зафиксировано. The following scenes run actual stand assertions.'
# A clean set of lab namespaces is required; cleanup is explicit and never
# modifies a workshop tenant, shared cluster component or non-lab namespace.
bash hack/e2e/run.sh "$RUN" \
  08-import 08-goshran 01-escalation 07-origin 17-agencies \
  03-sovereign-16k 02-throttle 04-whitelist 04-observe 04-ephemeral 04-werewolf \
  01-reestr 01-self-block 05-pigeon 06-calls 06-max \
  09-escrow-forever 10-drill 11-erid 11-blogger 12-cooling
export KUBECONFIG=/work/kube/rknetes.conf
/work/out/rknetes/rknetesctl --kubeconfig "$KUBECONFIG" -n lab-whitelist why gosuslugi | tee "/work/evidence/$RUN/why.txt"
/work/bin/kubectl --context admin@workshop -n lab-whitelist apply -f - <<'YAML'
apiVersion: rknetes.su/v1alpha1
kind: StatusStatement
metadata: {name: official}
spec: {subject: shop}
YAML
sleep 5
/work/bin/kubectl --context admin@workshop -n lab-whitelist get statusstatement official -o jsonpath='{.status.text}' | tee "/work/evidence/$RUN/statement.txt"
echo
