#!/usr/bin/env python3
"""Report actual upstream JUnit numbers; never substitute a target count."""
import json
import pathlib
import sys
import xml.etree.ElementTree as ET
root = pathlib.Path(sys.argv[1])
files = sorted(root.rglob('*.xml'))
rows = []
invalid = []
specs = {}
hook_failures = []
for path in files:
    try:
        tree = ET.parse(path)
    except ET.ParseError as error:
        invalid.append({'file': str(path.relative_to(root)), 'error': str(error)})
        continue
    cases = tree.findall('.//testcase')
    if not cases:
        continue
    skipped = sum(c.find('skipped') is not None for c in cases)
    failed = sum(c.find('failure') is not None or c.find('error') is not None for c in cases)
    rows.append({'file': str(path.relative_to(root)), 'total': len(cases), 'skipped': skipped,
                 'failed': failed, 'passed': len(cases)-skipped-failed})
    for case in cases:
        name = case.get('name', '')
        failed = case.find('failure') is not None or case.find('error') is not None
        if not name.startswith('[It] '):
            if failed:
                hook_failures.append(name)
            continue
        if name in specs:
            raise SystemExit('Duplicate spec in JUnit inputs: '+name)
        specs[name] = {'skipped': case.find('skipped') is not None, 'failed': failed}
if not rows:
    raise SystemExit('No JUnit results: conformance has not been established')
conformance = {name: value for name, value in specs.items() if '[Conformance]' in name}
passed = sum(not v['skipped'] and not v['failed'] for v in conformance.values())
failed = sum(v['failed'] for v in conformance.values())
skipped = sum(v['skipped'] for v in conformance.values())
exit_file = root/'exit-code'
runner_exit = int(exit_file.read_text()) if exit_file.exists() else None
report = {'suites': rows, 'invalid': invalid, 'targetPassed': 462,
          'upstreamConformanceTotal': len(conformance), 'passedConformance': passed,
          'failedConformance': failed, 'skippedConformance': skipped,
          'failedSpecs': [name for name, v in specs.items() if v['failed']],
          'suiteHookFailures': hook_failures, 'runnerExitCode': runner_exit,
          'conformant': (len(conformance) == passed == 462 and failed == skipped == 0
                        and not hook_failures and not invalid and runner_exit == 0)}
(root/'summary.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(report, indent=2))
