#!/usr/bin/env bash
set -euo pipefail
mkdir -p /runtime/www
printf 'real encapsulated application response\n' > /runtime/www/index.html
python3 -m http.server 8080 --directory /runtime/www >/runtime/http.log 2>&1 &
openvpn --dev tunovpn --dev-type tun --ifconfig 198.19.1.1 198.19.1.2 --proto udp --port 1194 --secret /keys/openvpn.key --cipher AES-256-CBC --auth SHA256 --verb 3 >/runtime/openvpn.log 2>&1 &
WG_PROCESS_FOREGROUND=1 wireguard-go wg0 >/runtime/wg.log 2>&1 &
for i in {1..30}; do ip link show wg0 >/dev/null 2>&1 && break; sleep 1; done
wg set wg0 private-key /keys/wg.key listen-port 51820 peer "$(cat /keys/peer.pub)" allowed-ips 198.19.2.2/32
ip address add 198.19.2.1/30 dev wg0
ip link set wg0 up
openssl s_server -accept 9444 -cert /keys/decoy.crt -key /keys/decoy.key -tls1_3 -alpn h2 -www >/runtime/decoy.log 2>&1 &
xray run -config /keys/xray.json >/runtime/xray.log 2>&1 &
iodined -f -c -P "$(cat /keys/password)" -d dns0 198.19.3.1/27 tunnel.lab >/runtime/dns.log 2>&1 &
ptunnel-ng -r127.0.0.1 -R8080 -P "$(cat /keys/password)" >/runtime/icmp.log 2>&1 &
wait
