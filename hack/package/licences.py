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


def fetch(url):
    with urllib.request.urlopen(url, timeout=25) as response:
        data = response.read(80 * 1024 * 1024 + 1)
    if len(data) > 80 * 1024 * 1024:
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
    args = parser.parse_args()
    with tarfile.open(args.inventory) as source:
        sbom = json.load(source.extractfile('sbom/native.syft.json'))
        upstream = source.extractfile('provenance/kubernetes-upstream-commit.txt').read().decode().strip()
        base = source.extractfile('provenance/kuberoot-base-commit.txt').read().decode().strip()
        components = source.extractfile('provenance/rknetes-components-commit.txt').read().decode().strip()
    records = {}
    for artifact in sbom['artifacts']:
        if artifact.get('licenses'):
            continue
        key = (artifact['name'], artifact['version'], artifact['type'])
        record = records.setdefault(key, {'name': key[0], 'version': key[1], 'type': key[2], 'instances': 0, 'embeddedH1': set()})
        record['instances'] += 1
        if value := artifact.get('metadata', {}).get('h1Digest'):
            record['embeddedH1'].add(value)
        settings = {s['key']: s['value'] for s in artifact.get('metadata', {}).get('goBuildSettings', [])}
        if settings.get('vcs.revision'):
            record['sourceRevision'] = settings['vcs.revision']
            record['sourceModified'] = settings.get('vcs.modified') == 'true'
    out = args.destination
    (out / 'texts').mkdir(parents=True, exist_ok=True)

    def recover(record):
        record['embeddedH1'] = sorted(record['embeddedH1'])
        name, version = record['name'], record['version']
        files = {}
        try:
            if name == 'rknetes.su/rknetes':
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
                    raw = fetch(url)
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
