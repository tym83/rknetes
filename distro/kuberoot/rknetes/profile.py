"""Derive the RKNetes node profile from the pinned kuberoot edge profile."""
import pathlib
import sys

profile = pathlib.Path(sys.argv[1]).read_text()
assert '  name: edge\n' in profile
profile = profile.replace('  name: edge\n', '  name: rknetes\n', 1)
# Keep the upstream API and node services; censorship is an opt-in lab add-on.
sys.stdout.write(profile)
