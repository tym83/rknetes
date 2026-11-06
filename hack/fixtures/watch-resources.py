#!/usr/bin/env python3
"""Exercise the explicit gateway from a Pod whose native API route is denied."""
import http.client
import json
import pathlib
import socket
import ssl
import sys
import time
from urllib.parse import urlencode

root=pathlib.Path('/keys')
gateway=sys.argv[1]
context=ssl.create_default_context(cafile=str(root/'gateway.crt'))
context.load_cert_chain(root/'client.crt',root/'client.key')
native_context=ssl.create_default_context(cafile=str(root/'native.crt'))
native_context.load_cert_chain(root/'client.crt',root/'client.key')
def native():
    connection=http.client.HTTPSConnection('10.96.0.1',443,context=native_context,timeout=3)
    try:
        connection.request('GET','/version')
        response=connection.getresponse();response.read();return response.status
    finally:connection.close()
if sys.argv[-1]=='native':
    assert native()==200
    print('PASS: native API is reachable before the explicit client routing policy')
    raise SystemExit
try:native()
except (TimeoutError,socket.timeout,OSError):print('PASS: selected client cannot reach the native API route')
else:raise AssertionError('native API route remained reachable')

def connection():
    # The serving certificate names the gateway, while the connection stays in
    # the nested Pod network. Wrap the actual socket with that explicit SNI.
    c=http.client.HTTPSConnection('watch-office.rknet-system.svc',9443,context=context,timeout=8)
    c.connect=lambda:setattr(c,'sock',context.wrap_socket(socket.create_connection((gateway,9443),8),server_hostname='watch-office.rknet-system.svc'))
    return c
def request(path,watch=False):
    c=connection();c.request('GET',path);r=c.getresponse()
    if watch:return c,r
    code=r.status;r.read();c.close();return code
def stage(value):pathlib.Path('/tmp/watch-stage').write_text(value)
def eventually(path,code):
    end=time.monotonic()+90
    while time.monotonic()<end:
        if request(path)==code:return
        time.sleep(1)
    raise AssertionError((path,code))

ns='lab-watch-resources'
for group,version,resource,registration in [('', 'v1','configmaps','cm-channel'),('apps','v1','deployments','deployment-channel'),('rknetes.su','v1alpha1','tunnelprofiles','custom-channel')]:
    prefix=('/apis/'+group+'/'+version) if group else '/api/'+version
    base=prefix+'/namespaces/'+ns+'/'+resource
    query=urlencode({'watch':'true','resourceVersion':'0','labelSelector':'channel=example','timeoutSeconds':'120'})
    first,response=request(base+'?'+query,True);assert response.status==200,response.status
    assert json.loads(response.readline())['type'] in ('ADDED','BOOKMARK')
    second,denied=request(base+'?'+urlencode({'watch':'true','resourceVersion':'0','fieldSelector':'metadata.name=channel'}),True)
    assert denied.status==451,denied.status;denied.read();second.close();first.close()
    assert request(base+'/channel')==451
    assert request(base+'?labelSelector=channel%3Dexample')==451
    stage(registration+'-blocked')
    eventually(base+'/channel',200)
    assert request(base+'?labelSelector=channel%3Dexample')==200
    print('PASS: aggregate watch, named watch, GET/list registration and recovery for',resource,flush=True)

base='/api/v1/namespaces/'+ns+'/configmaps'
query=urlencode({'watch':'true','sendInitialEvents':'true','resourceVersionMatch':'NotOlderThan','allowWatchBookmarks':'true','labelSelector':'late=example','timeoutSeconds':'120'})
opened=[]
for _ in range(2):
    c,r=request(base+'?'+query,True);assert r.status==200
    assert json.loads(r.readline())['type']=='BOOKMARK'
    opened.append((c,r))
stage('late-watch-ready')
eventually(base+'/late',451)
for c,_ in opened:c.close()
stage('late-channel-blocked')
eventually(base+'/late',200)
print('PASS: an object created after two collection subscriptions acquired its actual audience and required registration',flush=True)
stage('complete')
