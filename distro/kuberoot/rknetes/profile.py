"""Derive the RKNetes node profile from the pinned kuberoot edge profile."""
import pathlib
import sys

profile = pathlib.Path(sys.argv[1]).read_text()
assert '  name: edge\n' in profile
profile = profile.replace('  name: edge\n', '  name: rknetes\n', 1)
profile = profile.replace('/usr/bin/kube-apiserver', '/usr/bin/eo-server')
profile = profile.replace('/usr/bin/kube-scheduler', '/usr/bin/gosplan')
profile = profile.replace('/usr/bin/kubelet', '/usr/bin/uchastkovy')
# Component flags and structured versions retain upstream semantics.
sys.stdout.write(profile)
