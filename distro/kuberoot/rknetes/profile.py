"""Derive the RKNetes node profile from the pinned kuberoot edge profile."""
import pathlib
import sys

profile = pathlib.Path(sys.argv[1]).read_text()
assert '  name: edge\n' in profile
profile = profile.replace('  name: edge\n', '  name: rknetes\n', 1)
profile = profile.replace('/usr/bin/kube-apiserver', '/usr/bin/eo-server')
profile = profile.replace('/usr/bin/kube-scheduler', '/usr/bin/gosplan')
profile = profile.replace('/usr/bin/kubelet', '/usr/bin/uchastkovy')
profile = profile.replace('/usr/bin/etcd\n', '/usr/bin/prochee\n')
profile = profile.replace('/usr/bin/kube-controller-manager', '/usr/bin/kru')
profile = profile.replace('/usr/bin/kube-proxy', '/usr/bin/pochta')
profile = profile.replace('- /usr/bin/eo-server\n', '- /usr/bin/eo-server\n        - --audit-policy-file=/usr/share/rknetes/audit-policy.yaml\n        - --audit-log-path=/var/log/rknetes-audit.json\n        - --audit-log-maxsize=10\n        - --audit-log-maxbackup=2\n        - --audit-log-maxage=7\n')
# Component flags and structured versions retain upstream semantics.
sys.stdout.write(profile)
