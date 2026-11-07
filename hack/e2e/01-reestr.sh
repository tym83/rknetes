#!/usr/bin/env bash
# Prove that a retained IP policy denies packets after the original Pod is gone.
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=${RK_TEST_NAMESPACE:-lab-reestr}
new_namespace "$NS"
k label namespace "$NS" pod-security.kubernetes.io/enforce=privileged
fixture telegram
client
IP=$(k -n "$NS" get pod telegram -o jsonpath='{.status.podIP}')
NODE=$(k -n "$NS" get pod telegram -o jsonpath='{.spec.nodeName}')
probe "http://$IP:8080"
rknetesctl --kubeconfig "$KUBECONFIG" -n "$NS" block telegram
k -n "$NS" wait --for=condition=Applied reestrentry/telegram --timeout=60s
wait_until assert_blocked "http://$IP:8080"
# Reserve other free addresses through the real Cilium IPAM API, then let CNI
# allocate the only free address. Release only reservations created by this test.
AGENT=ipam-helper
k -n "$NS" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: ipam-helper}
spec:
  nodeName: $NODE
  containers:
  - name: helper
    image: nicolaka/netshoot:v0.14
    command: [sleep, '3600']
    volumeMounts: [{name: cilium, mountPath: /var/run/cilium}]
  volumes: [{name: cilium, hostPath: {path: /var/run/cilium, type: Directory}}]
YAML
k -n "$NS" wait --for=condition=Ready pod/ipam-helper --timeout=180s
k -n "$NS" delete pod telegram --wait=true
PREFIX=${IP%.*}
release_reservations() {
  k -n "$NS" exec "$AGENT" -- sh -c 'while read ip; do curl -fsS --unix-socket /var/run/cilium/cilium.sock -X DELETE "http://localhost/v1/ipam/$ip?pool=default"; done < /tmp/rknetes-ipam-reservations; rm /tmp/rknetes-ipam-reservations'
}
trap release_reservations EXIT
k -n "$NS" exec -i "$AGENT" -- sh -s -- "$PREFIX" "$IP" <<'SH'
set -eu
prefix=$1; target=$2
: > /tmp/rknetes-ipam-reservations
for suffix in $(seq 1 254); do
  ip=$prefix.$suffix
  [ "$ip" = "$target" ] && continue
  code=$(curl -s -o /tmp/rknetes-ipam-response -w '%{http_code}' --unix-socket /var/run/cilium/cilium.sock -X POST "http://localhost/v1/ipam/$ip?owner=rknetes-ip-reuse-test&pool=default")
  case "$code" in 200|201) echo "$ip" >> /tmp/rknetes-ipam-reservations;; 400|409|500) [ "$(cat /tmp/rknetes-ipam-response)" = '"provided IP is already allocated"' ] || { cat /tmp/rknetes-ipam-response; exit 1; };; *) cat /tmp/rknetes-ipam-response; exit 1;; esac
done
SH

k -n "$NS" run payment-api --image=busybox:1.37 --overrides="{\"spec\":{\"nodeName\":\"$NODE\"}}" --command -- sh -c 'mkdir -p /tmp/www; echo payment > /tmp/www/index.html; httpd -f -p 8080 -h /tmp/www'
k -n "$NS" wait --for=condition=Ready pod/payment-api --timeout=90s
[[ "$(k -n "$NS" get pod payment-api -o jsonpath='{.status.podIP}')" == "$IP" ]]
k -n "$NS" wait --for=condition=BornBlocked pod/payment-api --timeout=60s
assert_blocked "http://$IP:8080"
# Amnesty is annotation-driven and actually restores traffic.
k -n "$NS" patch reestrentry telegram --type merge -p '{"spec":{"podName":"payment-api"}}'
k -n "$NS" annotate pod payment-api rknetes.su/ready-to-counter-terrorism=true
wait_until probe "http://$IP:8080"
echo 'PASS: IP deny, IPAM reuse, BornBlocked and amnesty'
