#!/usr/bin/env bash
set -euo pipefail
set -x
# The only block device opened is allocated for this Pod's fixed-size file.
mkdir -p /private-disk /disk /tmp/cp
truncate -s 256M /private-disk/archive.img
mknod /dev/loop-control c 10 237 2>/dev/null || true
for i in $(seq 0 31); do mknod /dev/loop$i b 7 "$i" 2>/dev/null || true; done
LOOP=$(losetup --find --show /private-disk/archive.img)
cleanup(){ kill $(jobs -pr) 2>/dev/null || true; umount /disk || true; losetup -d "$LOOP"; }
trap cleanup EXIT
trap "exit 143" TERM INT
mkfs.ext4 -q -m 0 "$LOOP"
mount "$LOOP" /disk
mkdir -p /disk/archive /disk/etcd
openssl req -config /dev/null -x509 -newkey rsa:2048 -nodes -days 2 -keyout /tmp/cp/tls.key -out /tmp/cp/tls.crt -subj /CN=disposable-apiserver -addext 'subjectAltName=IP:127.0.0.1' >/dev/null
etcd --data-dir=/disk/etcd --listen-client-urls=http://127.0.0.1:2379 --advertise-client-urls=http://127.0.0.1:2379 --listen-peer-urls=http://127.0.0.1:2380 --initial-advertise-peer-urls=http://127.0.0.1:2380 --initial-cluster=default=http://127.0.0.1:2380 --quota-backend-bytes=1073741824 --max-wals=1 >/tmp/etcd.log 2>&1 &
echo $! >/tmp/etcd.pid
# The disposable API is reachable only from its own Pod; it is never registered
# as a node or control plane of either existing Kubernetes cluster.
eo-server --etcd-servers=http://127.0.0.1:2379 --bind-address=127.0.0.1 --advertise-address="$(hostname -i)" --secure-port=6444 --service-cluster-ip-range=198.19.0.0/24 --client-ca-file=/tmp/cp/tls.crt --authorization-mode=AlwaysAllow --anonymous-auth=true --tls-cert-file=/tmp/cp/tls.crt --tls-private-key-file=/tmp/cp/tls.key --service-account-key-file=/tmp/cp/tls.crt --service-account-signing-key-file=/tmp/cp/tls.key --service-account-issuer=https://disposable.lab --disable-admission-plugins=ServiceAccount >/tmp/apiserver.log 2>&1 &
python3 /scripts/server.py >/tmp/server.log 2>&1 &
/rk/archive-agent --policy full-disk --directory /disk/archive >/tmp/archive.log 2>&1 &
echo $! >/tmp/archive.pid
wait
