#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-key-refusal
new_namespace "$NS"
start_lab_controller
trap stop_lab_controller EXIT
k -n "$NS" run volatile-key --image=nicolaka/netshoot:v0.14 --command -- sh -ec 'umask 077; mkdir -p /tmp/tls; openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=lab-key-refusal -keyout /tmp/tls/key -out /tmp/tls/cert >/dev/null 2>&1; exec openssl s_server -accept 8080 -www -cert /tmp/tls/cert -key /tmp/tls/key'
k -n "$NS" wait --for=condition=Ready pod/volatile-key --timeout=180s
client
IP=$(k -n "$NS" get pod volatile-key -o jsonpath='{.status.podIP}')
probe() { k -n "$NS" exec client -- wget -q --no-check-certificate -T 3 -O /dev/null "$1"; }
wait_until probe "https://$IP:8080"
# The serving TLS key was generated inside the Pod and is absent from Secrets.
k -n "$NS" annotate pod volatile-key rknetes.su/tls-disclosure-required=true rknetes.su/key-escrow-secret=exported
k -n "$NS" wait --for=condition=RefusedToShareKeys pod/volatile-key --timeout=60s
wait_until assert_blocked "https://$IP:8080"
PRIVATE_DIR=$(mktemp -d /work/tls/disclosure.XXXXXX)
trap 'rm -rf "$PRIVATE_DIR"; stop_lab_controller' EXIT
# The contract exports the actual key bytes without writing them to logs/evidence.
k -n "$NS" exec volatile-key -- cat /tmp/tls/key > "$PRIVATE_DIR/key"
k -n "$NS" exec volatile-key -- cat /tmp/tls/cert > "$PRIVATE_DIR/cert"
k -n "$NS" create secret generic exported --type=kubernetes.io/tls --from-file=tls.key="$PRIVATE_DIR/key" --from-file=tls.crt="$PRIVATE_DIR/cert"
k -n "$NS" wait --for=condition=RefusedToShareKeys=False pod/volatile-key --timeout=60s
# Disclosure does not erase a historical IP ban: amnesty is still needed.
assert_blocked "https://$IP:8080"
k -n "$NS" annotate pod volatile-key rknetes.su/ready-to-counter-terrorism=true
wait_until probe "https://$IP:8080"
k -n "$NS" get reestrentries -o custom-columns=NAME:.metadata.name,REASON:.spec.reason
echo 'PASS: an unexported declared key causes real registry denial; escrow plus annotation amnesty restores packets'
