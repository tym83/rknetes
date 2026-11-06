#!/usr/bin/env python3
"""Recover licence evidence from exact module archives, without compiling code."""
import argparse
import base64
from concurrent.futures import ThreadPoolExecutor
import hashlib
import io
import json
from pathlib import Path
import re
import tarfile
import urllib.parse
import urllib.request
import zipfile


def escape(value):
    return ''.join('!' + c.lower() if c.isupper() else c for c in value)


def fetch(url, limit=80 * 1024 * 1024):
    with urllib.request.urlopen(url, timeout=25) as response:
        data = response.read(limit + 1)
    if len(data) > limit:
        raise ValueError('source archive exceeds the bounded download size')
    return data


def module_hash(archive):
    lines = []
    for name in sorted(n for n in archive.namelist() if not n.endswith('/')):
        digest = hashlib.sha256(archive.read(name)).hexdigest()
        lines.append(f'{digest}  {name}\n')
    return 'h1:' + base64.b64encode(hashlib.sha256(''.join(lines).encode()).digest()).decode()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('inventory', type=Path)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--native-root', type=Path)
    parser.add_argument('--resume', action='store_true')
    args = parser.parse_args()
    with tarfile.open(args.inventory) as source:
        sbom = json.load(source.extractfile('sbom/native.syft.json'))
        upstream = source.extractfile('provenance/kubernetes-upstream-commit.txt').read().decode().strip()
        base = source.extractfile('provenance/kuberoot-base-commit.txt').read().decode().strip()
        components = source.extractfile('provenance/rknetes-components-commit.txt').read().decode().strip()
        root_sha = json.load(source.extractfile('sbom/summary.json'))['rootfsSHA256']
    if args.native_root:
        assert args.native_root.name == root_sha, 'native root must be the hash-named extraction of this inventory'
    records = {}
    for artifact in sbom['artifacts']:
        if artifact.get('licenses'):
            continue
        key = (artifact['name'], artifact['version'], artifact['type'])
        record = records.setdefault(key, {'name': key[0], 'version': key[1], 'type': key[2], 'instances': 0, 'embeddedH1': set()})
        record['instances'] += 1
        record.setdefault('locations', []).extend(x['path'] for x in artifact.get('locations', []))
        if value := artifact.get('metadata', {}).get('h1Digest'):
            record['embeddedH1'].add(value)
        settings = {s['key']: s['value'] for s in artifact.get('metadata', {}).get('goBuildSettings', [])}
        if settings.get('vcs.revision'):
            record['sourceRevision'] = settings['vcs.revision']
            record['sourceModified'] = settings.get('vcs.modified') == 'true'
    out = args.destination
    (out / 'texts').mkdir(parents=True, exist_ok=True)
    previous = {}
    if args.resume and (out / 'report.json').is_file():
        report = json.loads((out / 'report.json').read_text())
        assert report['inventorySHA256'] == hashlib.sha256(args.inventory.read_bytes()).hexdigest()
        previous = {(r['name'], r['version'], r['type']): r for r in report['records']}

    def recover(record):
        old = previous.get((record['name'], record['version'], record['type']))
        if old and old['result'] != 'unresolved' and all(hashlib.sha256((out / f['evidencePath']).read_bytes()).hexdigest() == f['sha256'] for f in old['files']):
            return old
        record['embeddedH1'] = sorted(record['embeddedH1'])
        record['locations'] = sorted(set(record.get('locations', [])))
        name, version = record['name'], record['version']
        files = {}
        try:
            if args.native_root and (name == 'go' or version == 'UNKNOWN') and record['locations'] and all(p.startswith('/usr/lib/go/') and '/vendor/' not in p for p in record['locations']):
                root = args.native_root / 'usr/lib/go'
                record['sourceVersion'] = (root / 'VERSION').read_text().splitlines()[0]
                record['sourceURL'] = f'https://github.com/golang/go/tree/{record["sourceVersion"]}'
                record['scope'] = 'Go toolchain binary, standard-library generator or test fixture; root notice from the exact shipped compiler tree'
                files['usr/lib/go/LICENSE'] = (root / 'LICENSE').read_bytes()
            elif record['type'] == 'npm':
                metadata = json.loads(fetch(f'https://registry.npmjs.org/{urllib.parse.quote(name, safe="")}/{version}'))
                record['sourceURL'] = metadata['dist']['tarball']
                raw = fetch(record['sourceURL'])
                algorithm, expected = metadata['dist']['integrity'].split('-', 1)
                assert base64.b64encode(hashlib.new(algorithm, raw).digest()).decode() == expected
                record['registryIntegrityVerified'] = metadata['dist']['integrity']
                record['sourceSHA256'] = hashlib.sha256(raw).hexdigest()
                record['declaredLicense'] = metadata.get('license')
                record['scope'] = 'Dependency in the shipped Go telemetry package-lock; this does not assert installed JavaScript runtime code'
                with tarfile.open(fileobj=io.BytesIO(raw)) as archive:
                    for member in archive.getmembers():
                        if member.isfile() and member.size <= 1024 * 1024 and re.match(r'^(LICENSE|LICENCE|COPYING|NOTICE)(\.|$)', Path(member.name).name, re.I):
                            files[member.name] = archive.extractfile(member).read()
            elif name.startswith('github.com/grafana/grafana') and version == 'UNKNOWN' or name == 'xorm.io/xorm' and version == 'UNKNOWN':
                relative = 'pkg/util/xorm' if name == 'xorm.io/xorm' else name.removeprefix('github.com/grafana/grafana').lstrip('/')
                record['sourceVersion'] = 'v11.5.2'
                record['sourceURL'] = 'https://github.com/grafana/grafana/tree/v11.5.2/' + relative
                record['scope'] = 'Local workspace module in the checksum-pinned Grafana11.5.2 binary; nearest source licence, without overriding per-file notices'
                parts = Path(relative).parts
                for length in range(len(parts), -1, -1):
                    path = '/'.join((*parts[:length], 'LICENSE'))
                    try:
                        files[path] = fetch('https://raw.githubusercontent.com/grafana/grafana/v11.5.2/' + path)
                        break
                    except urllib.error.HTTPError as error:
                        if error.code != 404:
                            raise
            elif name == 'github.com/docker/cli/cmd/docker':
                record['sourceVersion'] = 'v28.0.1'
                record['sourceURL'] = 'https://raw.githubusercontent.com/docker/cli/v28.0.1/LICENSE'
                record['scope'] = 'Docker CLI28.0.1/068a01e identified by the shipped executable build flags'
                files['LICENSE'] = fetch(record['sourceURL'])
            elif name == 'helm.sh/helm/v3' and record.get('sourceRevision'):
                record['sourceURL'] = f'https://raw.githubusercontent.com/helm/helm/{record["sourceRevision"]}/LICENSE'
                files['LICENSE'] = fetch(record['sourceURL'])
            elif name == 'rknetes.su/rknetes':
                record['sourceRevision'] = components
                record['sourceURL'] = 'repository:LICENSE'
                files['LICENSE'] = Path('LICENSE').read_bytes()
            elif name == 'busybox':
                record['sourceURL'] = f'https://busybox.net/downloads/busybox-{version}.tar.bz2'
                raw = fetch(record['sourceURL'])
                record['sourceSHA256'] = hashlib.sha256(raw).hexdigest()
                with tarfile.open(fileobj=io.BytesIO(raw)) as archive:
                    for member in archive.getmembers():
                        if member.isfile() and Path(member.name).name in ['LICENSE', 'COPYING', 'NOTICE']:
                            files[member.name] = archive.extractfile(member).read()
            elif name == 'github.com/kuberoot-dev/kuberoot' or name.startswith('k8s.io/') and (version == 'UNKNOWN' or name == 'k8s.io/kubernetes'):
                repo, revision = ('kuberoot-dev/kuberoot', base) if name.endswith('/kuberoot') else ('kubernetes/kubernetes', upstream)
                record['sourceRevision'] = revision
                record['sourceURL'] = f'https://raw.githubusercontent.com/{repo}/{revision}/LICENSE'
                files['LICENSE'] = fetch(record['sourceURL'])
                record['scope'] = 'root licence; build patch and local staging provenance remain in the original archive'
            else:
                if version.endswith('+dirty'):
                    revision = record['sourceRevision']
                    repo = name.removeprefix('github.com/')
                    record['sourceURL'] = f'https://raw.githubusercontent.com/{repo}/{revision}/LICENSE'
                    files['LICENSE'] = fetch(record['sourceURL'])
                    record['scope'] = 'root licence at recorded revision; local dirty diff requires build-source evidence'
                else:
                    url = f'https://proxy.golang.org/{escape(name)}/@v/{escape(version)}.zip'
                    record['sourceURL'] = url
                    raw = fetch(url, 384 * 1024 * 1024 if name == 'github.com/RoaringBitmap/roaring' else 80 * 1024 * 1024)
                    record['sourceSHA256'] = hashlib.sha256(raw).hexdigest()
                    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
                        digest = module_hash(archive)
                        record['archiveH1'] = digest
                        if record['embeddedH1'] and record['embeddedH1'] != [digest]:
                            raise ValueError('downloaded source does not match the binary embedded h1 digest')
                        record['embeddedDigestVerified'] = bool(record['embeddedH1'])
                        for filename in archive.namelist():
                            if re.match(r'^(LICENSE|LICENCE|COPYING|NOTICE)(\.|$)', Path(filename).name, re.I):
                                if archive.getinfo(filename).file_size <= 1024 * 1024:
                                    files[filename] = archive.read(filename)
                        if not files and name.startswith('buf.build/gen/go/parca-dev/parca/'):
                            record['scope'] = 'Generated SDK has no root licence file. Preserve exact-schema notices and the generator licence; no blanket SPDX conclusion.'
                            proto_name = 'buf.build/gen/go/parca-dev/parca/protocolbuffers/go'
                            proto_version = 'v1.34.2-20240902100956-02fd72488966.2'
                            proto_raw = fetch(f'https://proxy.golang.org/{proto_name}/@v/{proto_version}.zip')
                            record['schemaModuleSHA256'] = hashlib.sha256(proto_raw).hexdigest()
                            with zipfile.ZipFile(io.BytesIO(proto_raw)) as schema:
                                for filename in schema.namelist():
                                    if filename.endswith('.go'):
                                        header = schema.read(filename).decode().split('\npackage ', 1)[0]
                                        if 'Licensed under the Apache License' in header:
                                            files[filename + '.notice'] = header.encode()
                            generator = 'connectrpc/connect-go/v1.17.0' if '/connectrpc/' in name else 'protocolbuffers/protobuf-go/v1.34.2'
                            repo, tag = generator.rsplit('/', 1)
                            files['generator-LICENSE'] = fetch(f'https://raw.githubusercontent.com/{repo}/{tag}/LICENSE')
                            files['schema-Apache-2.0'] = fetch('https://www.apache.org/licenses/LICENSE-2.0.txt')
            if not files:
                raise ValueError('no licence text in the exact source archive')
            record['files'] = []
            for filename, data in sorted(files.items()):
                digest = hashlib.sha256(data).hexdigest()
                destination = out / 'texts' / (digest + '.txt')
                destination.write_bytes(data)
                record['files'].append({'sourcePath': filename, 'sha256': digest, 'evidencePath': 'texts/' + destination.name})
            record['result'] = 'exact-source-licence-text-collected'
        except Exception as error:
            record['result'] = 'unresolved'
            record['error'] = str(error)
        print(record['result'], name, version, flush=True)
        return record

    with ThreadPoolExecutor(max_workers=4) as pool:
        result = sorted(pool.map(recover, records.values()), key=lambda r: (r['name'], r['version']))
    summary = {
        'inventorySHA256': hashlib.sha256(args.inventory.read_bytes()).hexdigest(),
        'missingInstancesBefore': sum(r['instances'] for r in result),
        'recoveredInstances': sum(r['instances'] for r in result if r['result'] != 'unresolved'),
        'unresolvedInstances': sum(r['instances'] for r in result if r['result'] == 'unresolved'),
        'scope': 'Exact source licence texts; no automated legal conclusion or blanket SPDX classification.',
        'records': result,
    }
    (out / 'report.json').write_text(json.dumps(summary, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps({k: v for k, v in summary.items() if k != 'records'}, indent=2))


if __name__ == '__main__':
    main()
