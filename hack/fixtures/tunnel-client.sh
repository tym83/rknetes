#!/usr/bin/env bash
set -euo pipefail
openvpn --dev tunovpn --dev-type tun --ifconfig 198.19.1.2 198.19.1.1 --proto udp --remote "$SERVER_IP" 1194 --secret /keys/openvpn.key --cipher AES-256-CBC --auth SHA256 --verb 3 >/runtime/openvpn.log 2>&1 &
WG_PROCESS_FOREGROUND=1 wireguard-go wg0 >/runtime/wg.log 2>&1 &
for i in {1..30}; do ip link show wg0 >/dev/null 2>&1 && break; sleep 1; done
wg set wg0 private-key /keys/wg.key peer "$(cat /keys/peer.pub)" endpoint "$SERVER_IP:51820" allowed-ips 198.19.2.1/32 persistent-keepalive 1
ip address add 198.19.2.2/30 dev wg0
ip link set wg0 up
sed "s/SERVER_IP/$SERVER_IP/g" /keys/xray.json >/runtime/xray.json
xray run -config /runtime/xray.json >/runtime/xray.log 2>&1 &
iodine -f -r -P "$(cat /keys/password)" -d dns0 -T TXT -m 512 -L 0 "$SERVER_IP" tunnel.lab >/runtime/dns.log 2>&1 &
ptunnel-ng -p "$SERVER_IP" -l 1086 -r127.0.0.1 -R8080 -P "$(cat /keys/password)" >/runtime/icmp.log 2>&1 &
/rk/tunnel-probe --config /keys/probes.json --listen :7777 &
wait
