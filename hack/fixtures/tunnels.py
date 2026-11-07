#!/usr/bin/env python3
"""Generate private, lab-only protocol endpoints. Never print their secrets."""
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import uuid

root = Path(sys.argv[1])
assert str(root).startswith('/work/tls/')
os.umask(0o077)
server, client = root/'server', root/'client'
server.mkdir(parents=True, exist_ok=True)
client.mkdir(parents=True, exist_ok=True)
def run(*args, data=None):
    return subprocess.check_output(args, input=data, stderr=subprocess.DEVNULL).decode().strip()
def write(path, data):
    path.write_text(data if isinstance(data, str) else json.dumps(data))

subprocess.run(['openvpn', '--genkey', 'secret', str(server/'openvpn.key')], check=True, stdout=subprocess.DEVNULL)
write(client/'openvpn.key', (server/'openvpn.key').read_text())
for side in (server, client):
    write(side/'wg.key', run('wg', 'genkey'))
write(server/'peer.pub', run('wg','pubkey',data=(client/'wg.key').read_bytes()))
write(client/'peer.pub', run('wg','pubkey',data=(server/'wg.key').read_bytes()))
pair=dict(line.split(': ',1) for line in run('/work/out/tools/xray','x25519').splitlines())
password=secrets.token_urlsafe(24)
identity=str(uuid.uuid4())
for side in (server,client):
    write(side/'password',password)
subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(server/'decoy.key'),'-out',str(server/'decoy.crt'),'-days','2','-subj','/CN=gosuslugi.lab','-addext','subjectAltName=DNS:gosuslugi.lab,DNS:reality.lab'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
inbounds=[{'listen':'0.0.0.0','port':8388,'protocol':'shadowsocks','settings':{'method':'aes-128-gcm','password':password,'network':'tcp'}}]
outbounds=[]
client_inbounds=[]
routing=[]
for port,local,name,host in [(8443,1081,'VLESSReality','reality.lab'),(8444,1082,'Gosuslugi','gosuslugi.lab')]:
    inbounds.append({'listen':'0.0.0.0','port':port,'protocol':'vless','settings':{'clients':[{'id':identity}],'decryption':'none'},'streamSettings':{'network':'tcp','security':'reality','realitySettings':{'show':False,'dest':'127.0.0.1:9444','xver':0,'serverNames':[host],'privateKey':pair['Private key'],'shortIds':['0123456789abcdef']}}})
    client_inbounds.append({'tag':name,'listen':'127.0.0.1','port':local,'protocol':'socks','settings':{'auth':'noauth','udp':False}})
    outbounds.append({'tag':name,'protocol':'vless','settings':{'vnext':[{'address':'SERVER_IP','port':port,'users':[{'id':identity,'encryption':'none'}]}]},'streamSettings':{'network':'tcp','security':'reality','realitySettings':{'fingerprint':'chrome','serverName':host,'publicKey':pair['Public key'],'shortId':'0123456789abcdef'}}})
    routing.append({'type':'field','inboundTag':[name],'outboundTag':name})
client_inbounds.append({'tag':'Shadowsocks','listen':'127.0.0.1','port':1080,'protocol':'socks','settings':{'auth':'noauth','udp':False}})
outbounds.append({'tag':'Shadowsocks','protocol':'shadowsocks','settings':{'servers':[{'address':'SERVER_IP','port':8388,'method':'aes-128-gcm','password':password}]}})
routing.append({'type':'field','inboundTag':['Shadowsocks'],'outboundTag':'Shadowsocks'})
write(server/'xray.json',{'log':{'loglevel':'warning'},'inbounds':inbounds,'outbounds':[{'protocol':'freedom'}]})
write(client/'xray.json',{'log':{'loglevel':'warning'},'inbounds':client_inbounds,'outbounds':outbounds,'routing':{'rules':routing}})
write(client/'probes.json',{
    'OpenVPN':{'url':'http://198.19.1.1:8080','interface':'tunovpn'},
    'WireGuard':{'url':'http://198.19.2.1:8080','interface':'wg0'},
    'Shadowsocks':{'url':'http://127.0.0.1:8080','proxy':'socks5h://127.0.0.1:1080'},
    'VLESSReality':{'url':'http://127.0.0.1:8080','proxy':'socks5h://127.0.0.1:1081'},
    'Gosuslugi':{'url':'http://127.0.0.1:8080','proxy':'socks5h://127.0.0.1:1082'},
    'DNS':{'url':'http://198.19.3.1:8080','interface':'dns0'},
    'ICMP':{'url':'http://127.0.0.1:1086'},
})
print('Private protocol configuration generated; no key material written to evidence or HTTP output')
