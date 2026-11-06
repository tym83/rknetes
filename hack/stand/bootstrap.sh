#!/usr/bin/env bash
# Run in the builder after the three nodes have booted. No credentials go to stdout.
set -euo pipefail
export PATH=/work/bin:$PATH
STAGE=${1:?install or configure stage}; shift
CP_IP=${1:?control plane VM IP}
W1_IP=${2:?worker 1 VM IP}
W2_IP=${3:?worker 2 VM IP}
KUBE_DIR=$(dirname "${RKNETES_KUBECONFIG:-/work/kube/rknetes.conf}")
case "$KUBE_DIR" in /work/kube|/work/cleanroom/kube) ;; *) exit 2 ;; esac
mkdir -p "$KUBE_DIR"
cp /work/trust/admin.kubeconfig $KUBE_DIR/node.conf
kubectl --context admin@workshop --kubeconfig $KUBE_DIR/node.conf config rename-context kuberoot admin@workshop >/dev/null
node() { local address=$1; shift; kubectl --context admin@workshop --kubeconfig $KUBE_DIR/node.conf --server "https://$address:50000" --request-timeout=15s "$@"; }
if [[ "$STAGE" == install ]]; then
  for address in "$CP_IP" "$W1_IP" "$W2_IP"; do
    node "$address" get disks -o json > $KUBE_DIR/disks.json
    python3 -c 'import json,sys; ds=json.load(open(sys.argv[1]))["items"]; d=next(x for x in ds if x["metadata"]["name"]=="vdb"); assert not d.get("status",{}).get("role"), "system disk is not empty"' "$KUBE_DIR/disks.json"
  done
  for address in "$CP_IP" "$W1_IP" "$W2_IP"; do
    name=$(node "$address" get osconfig -o jsonpath='{.items[0].metadata.name}')
    node "$address" patch osconfig "$name" --type merge -p '{"spec":{"nameservers":["1.1.1.1","8.8.8.8"]}}'
    node "$address" create -f - <<'YAML'
apiVersion: node.kuberoot.dev/v1alpha1
kind: Installation
metadata: {name: system}
spec: {disk: vdb, reboot: false}
YAML
  done
  for address in "$CP_IP" "$W1_IP" "$W2_IP"; do
    ready=false
    for _ in $(seq 1 90); do
      phase=$(node "$address" get installation system -o jsonpath='{.status.phase}')
      if [[ "$phase" == Completed ]]; then ready=true; break; fi
      [[ "$phase" != Failed ]] || { node "$address" get installation system -o yaml; exit 1; }
      sleep 3
    done
    [[ "$ready" == true ]] || exit 1
  done
  echo 'Installations complete; boot the system disks before configure.'
  exit 0
fi
[[ "$STAGE" == configure ]] || exit 2
for address in "$CP_IP" "$W1_IP" "$W2_IP"; do
  ready=false
  for _ in $(seq 1 90); do
    if node "$address" get bootentries -o json > $KUBE_DIR/install.json 2>/dev/null && python3 -c 'import json,sys; a=json.load(open(sys.argv[1])); exit(not any(x.get("status",{}).get("booted",False) for x in a["items"]))' "$KUBE_DIR/install.json"; then ready=true; break; fi
    sleep 3
  done
  [[ "$ready" == true ]] || exit 1
done
node "$CP_IP" get kubeconfig admin -o jsonpath='{.kubeconfig}' > $KUBE_DIR/rknetes.conf
chmod 600 "$KUBE_DIR"/*.conf
old=$(kubectl --context admin@workshop --kubeconfig $KUBE_DIR/rknetes.conf config current-context)
if [[ "$old" != admin@workshop ]]; then kubectl --context admin@workshop --kubeconfig $KUBE_DIR/rknetes.conf config rename-context "$old" admin@workshop >/dev/null; fi
export KUBECONFIG=$KUBE_DIR/rknetes.conf
k() { kubectl --context admin@workshop "$@"; }
k -n kube-system create configmap rknetes-stand --from-literal=scope=nested-only --from-literal=podCIDR=10.42.0.0/16 --from-literal=serviceCIDR=10.96.0.0/12 --dry-run=client -o yaml | k apply -f -
for address in "$W1_IP" "$W2_IP"; do
  name=$(node "$address" get osconfigs -o jsonpath='{.items[0].metadata.name}')
  if [[ -n "${RK_MAX_ENROLLMENT_SERVER:-}" ]]; then
    membership="$KUBE_DIR/max-membership-$name.yaml"
    /work/out/optional/max-enroll --kubeconfig "$KUBE_DIR/rknetes.conf" --context admin@workshop \
      --node-kubeconfig "$KUBE_DIR/node.conf" --node-server "https://$CP_IP:50000" --node-name "$name" \
      --max-server "$RK_MAX_ENROLLMENT_SERVER" --max-ca "${RK_MAX_ENROLLMENT_CA:?}" \
      --session-file "${RK_MAX_ENROLLMENT_SESSION:?}" --failure-policy "${RK_MAX_ENROLLMENT_FAILURE_POLICY:-Closed}" --output "$membership"
    node "$address" create -f "$membership"
    continue
  fi
  node "$CP_IP" create -f - <<YAML
apiVersion: node.kuberoot.dev/v1alpha1
kind: JoinTicket
metadata: {name: $name}
spec: {nodeName: $name, role: Worker}
YAML
  node "$CP_IP" get jointicket "$name" -o jsonpath='{.status.membership}' | node "$address" create -f -
done
bash /work/src/rknetes/hack/stand/cilium.sh "$CP_IP"
k wait --for=condition=Ready nodes --all --timeout=180s
k get nodes -o wide
