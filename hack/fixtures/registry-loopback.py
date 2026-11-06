#!/usr/bin/env python3
"""Expose one private lab registry on this nested node's loopback only."""
import ipaddress
import select
import socket
import sys
import threading

target=sys.argv[1]
assert ipaddress.ip_address(target) in ipaddress.ip_network('10.42.0.0/16')
listener=socket.socket();listener.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
listener.bind(('127.0.0.1',5008));listener.listen(32)
def relay(client):
    upstream=None
    try:
        upstream=socket.create_connection((target,5000),5)
        while True:
            ready,_,_=select.select([client,upstream],[],[],60)
            if not ready:return
            for source in ready:
                data=source.recv(65536)
                if not data:return
                (upstream if source is client else client).sendall(data)
    finally:
        client.close()
        if upstream:upstream.close()
while True:
    client,_=listener.accept()
    threading.Thread(target=relay,args=(client,),daemon=True).start()
