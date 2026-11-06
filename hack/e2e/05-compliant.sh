#!/usr/bin/env bash
# Reuse the real Shadowsocks endpoints from the completed protocol ladder.
set -euo pipefail
source "$(dirname "$0")/common.sh"
NS=lab-tunnel-client
GATEWAY=lab-tunnel-server
[[ "$(k get ns "$NS" -o jsonpath='{.metadata.labels.rknetes\.su/lab}')" == true ]]
k -n "$NS" delete ciliumnetworkpolicy protocol-blocks --ignore-not-found
start_lab_controller
trap stop_lab_controller EXIT
fixture blocked-app
IP=$(k -n "$NS" get pod blocked-app -o jsonpath='{.status.podIP}')
direct() { k -n "$NS" exec agent -- curl -fsS --max-time 3 "http://$IP:8080"; }
tunnel() { k -n "$NS" exec agent -- curl -fsS --max-time 3 --socks5-hostname 127.0.0.1:1080 "http://$IP:8080"; }
wait_until direct
wait_until tunnel
k -n "$NS" apply -f - <<'YAML'
apiVersion: rknetes.su/v1alpha1
kind: ReestrEntry
metadata: {name: target}
spec: {podName: blocked-app, escalate: false}
YAML
denied_direct() { ! direct; }
denied_tunnel() { ! tunnel; }
wait_until denied_direct
tunnel
echo 'PASS: real Shadowsocks reaches the registered app from a separate namespace'
k -n "$NS" apply -f - <<YAML
apiVersion: rknetes.su/v1alpha1
kind: TunnelProfile
metadata: {name: lawful}
spec: {compliant: true, gatewayNamespace: $GATEWAY, gatewaySelector: {app: gosuslugi}}
YAML
wait_until denied_tunnel
k -n "$GATEWAY" get ciliumnetworkpolicies -o json
echo 'PASS: compliant gateway copied the active registry and denied the same actual request'
k -n "$NS" annotate pod blocked-app rknetes.su/ready-to-counter-terrorism=true
wait_until direct
wait_until tunnel
k -n "$NS" delete tunnelprofile lawful --wait=true --timeout=60s
[[ "$(k -n "$GATEWAY" get ciliumnetworkpolicies -o jsonpath='{.items}')" == '[]' ]]
echo 'PASS: amnesty restored direct and compliant traffic; finalizer removed the gateway policy'
