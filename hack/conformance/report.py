#!/usr/bin/env python3
"""Report actual upstream JUnit numbers; never substitute a target count."""
import json
import pathlib
import sys
import xml.etree.ElementTree as ET
root = pathlib.Path(sys.argv[1])
files = sorted(root.rglob('*.xml'))
rows = []
for path in files:
    tree = ET.parse(path)
    cases = tree.findall('.//testcase')
    if not cases:
        continue
    skipped = sum(c.find('skipped') is not None for c in cases)
    failed = sum(c.find('failure') is not None or c.find('error') is not None for c in cases)
    rows.append({'file': str(path.relative_to(root)), 'total': len(cases), 'skipped': skipped,
                 'failed': failed, 'passed': len(cases)-skipped-failed})
if not rows:
    raise SystemExit('No JUnit results: conformance has not been established')
report = {'suites': rows, 'targetPassed': 462}
(root/'summary.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(report, indent=2))
