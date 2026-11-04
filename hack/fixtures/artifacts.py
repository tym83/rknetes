#!/usr/bin/env python3
"""A valid OCI image and Helm chart, served through separate lab redirect hops."""
import argparse
import gzip
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import ipaddress
import json
import os
from pathlib import Path
import tarfile
from urllib.parse import urlparse


def digest(data):
    return 'sha256:' + hashlib.sha256(data).hexdigest()


def tar_bytes(entries):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode='w', format=tarfile.PAX_FORMAT) as archive:
        for name, data, mode in entries:
            info = tarfile.TarInfo(name)
            info.mode = mode
            if isinstance(data, str):
                info.type = tarfile.SYMTYPE
                info.linkname = data
                archive.addfile(info)
            else:
                info.size = len(data)
                archive.addfile(info, io.BytesIO(data))
    return output.getvalue()


def prepare(directory, busybox):
    directory.mkdir(parents=True, exist_ok=True)
    # Deterministic, poorly compressible fixture bytes; no user or secret data.
    payload = b''.join(hashlib.sha256(str(i).encode()).digest() for i in range(32768))
    layer = tar_bytes([('bin/busybox', busybox.read_bytes(), 0o755), ('bin/sh', 'busybox', 0o777),
                       ('bin/sleep', 'busybox', 0o777), ('payload', payload, 0o644)])
    compressed = gzip.compress(layer, mtime=0)
    config = json.dumps({'architecture': 'amd64', 'os': 'linux',
                         'config': {'Cmd': ['/bin/sleep', '3600']},
                         'rootfs': {'type': 'layers', 'diff_ids': [digest(layer)]}}).encode()
    manifest = json.dumps({'schemaVersion': 2, 'mediaType': 'application/vnd.oci.image.manifest.v1+json',
                           'config': {'mediaType': 'application/vnd.oci.image.config.v1+json', 'digest': digest(config), 'size': len(config)},
                           'layers': [{'mediaType': 'application/vnd.oci.image.layer.v1.tar+gzip', 'digest': digest(compressed), 'size': len(compressed)}]}).encode()
    chart = gzip.compress(tar_bytes([
        ('shop/Chart.yaml', b'apiVersion: v2\nname: shop\nversion: 0.1.0\ntype: application\n', 0o644),
        ('shop/values.yaml', b'{}\n', 0o644),
        ('shop/templates/receipt.yaml', b'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: shop-receipt\ndata:\n  status: delivered\n', 0o644),
        ('shop/files/payload', payload, 0o644),
    ]), mtime=0)
    for data in [compressed, config]:
        (directory / digest(data).replace(':', '-')).write_bytes(data)
    (directory / 'manifest.json').write_bytes(manifest)
    (directory / 'shop-0.1.0.tgz').write_bytes(chart)
    result = {'manifestDigest': digest(manifest), 'layerDigest': digest(compressed), 'layerSize': len(compressed),
              'chartSHA256': hashlib.sha256(chart).hexdigest(), 'chartSize': len(chart)}
    (directory / 'subjects.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))


def serve(directory, role, cdn, port):
    parsed = urlparse(cdn)
    if role == 'registry':
        if parsed.scheme != 'http' or not parsed.hostname or ipaddress.ip_address(parsed.hostname) not in ipaddress.ip_network('10.42.0.0/16'):
            raise ValueError('registry redirects require an explicit nested lab Pod IP')
    subjects = json.loads((directory / 'subjects.json').read_text())

    class Handler(BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'

        def do_HEAD(self):
            self.do_GET()

        def do_GET(self):
            path = urlparse(self.path).path
            location, data, content_type, content_digest = None, b'', 'application/octet-stream', None
            if path in ['/healthz', '/v2/']:
                data = b'ok' if path == '/healthz' else b'{}'
            elif path == '/subjects.json':
                data = (directory / 'subjects.json').read_bytes()
                content_type = 'application/json'
            elif role == 'registry' and path == '/index.yaml':
                data = ('apiVersion: v1\nentries:\n  shop:\n  - apiVersion: v2\n    name: shop\n    version: 0.1.0\n'
                        f'    digest: {subjects["chartSHA256"]}\n    urls: ["{cdn}/charts/shop-0.1.0.tgz"]\n').encode()
                content_type = 'application/yaml'
            elif role == 'registry' and path.startswith('/v2/lab/shop/manifests/') and path.rsplit('/', 1)[1] in ['1', subjects['manifestDigest']]:
                data = (directory / 'manifest.json').read_bytes()
                content_type = 'application/vnd.oci.image.manifest.v1+json'
                content_digest = subjects['manifestDigest']
            elif role == 'registry' and path.startswith('/v2/lab/shop/blobs/'):
                name = path.rsplit('/', 1)[1]
                if not (directory / name.replace(':', '-')).is_file():
                    self.send_error(404)
                    return
                location = cdn + '/blobs/' + name
            elif role == 'cdn' and (path.startswith('/blobs/sha256:') or path == '/charts/shop-0.1.0.tgz'):
                name = path.rsplit('/', 1)[1].replace(':', '-')
                if '/' in name or '..' in name or not (directory / name).is_file():
                    self.send_error(404)
                    return
                data = (directory / name).read_bytes()
            else:
                self.send_error(404)
                return
            self.send_response(307 if location else 200)
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Content-Type', content_type)
            self.send_header('Docker-Distribution-Api-Version', 'registry/2.0')
            if location:
                self.send_header('Location', location)
            if content_digest:
                self.send_header('Docker-Content-Digest', content_digest)
            self.end_headers()
            if self.command != 'HEAD':
                try:
                    for start in range(0, len(data), 1000):
                        self.wfile.write(data[start:start + 1000])
                        self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError):
                    pass

    ThreadingHTTPServer(('0.0.0.0', port), Handler).serve_forever()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--prepare', type=Path, metavar='BUSYBOX')
    parser.add_argument('--role', choices=['registry', 'cdn'], default='cdn')
    parser.add_argument('--cdn', default=os.environ.get('CDN_URL', ''))
    parser.add_argument('--port', type=int, default=8080)
    args = parser.parse_args()
    if args.prepare:
        prepare(args.directory, args.prepare)
    else:
        serve(args.directory, args.role, args.cdn, args.port)
