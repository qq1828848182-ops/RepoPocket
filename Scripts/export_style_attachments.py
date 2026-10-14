"""Export only the three fixed-data native swipe screenshots from Xcode 15."""
import json
from pathlib import Path
import subprocess
import sys

bundle, output = sys.argv[1:]
destination = Path(output)
destination.mkdir(parents=True, exist_ok=True)
pending = [None]
seen = set()
exported = set()

while pending:
    reference = pending.pop()
    if reference in seen:
        continue
    seen.add(reference)
    command = ['xcrun', 'xcresulttool', 'get', '--path', bundle, '--format', 'json']
    if reference:
        command += ['--id', reference]
    tree = json.loads(subprocess.check_output(command))
    stack = [tree]
    while stack:
        item = stack.pop()
        if isinstance(item, list):
            stack.extend(item)
        elif isinstance(item, dict):
            for key in ['testsRef', 'summaryRef']:
                ref = item.get(key, {}).get('id', {}).get('_value')
                if ref:
                    pending.append(ref)
            name = item.get('name', {}).get('_value', '')
            payload = item.get('payloadRef', {}).get('id', {}).get('_value')
            if payload and name in {'swipe-first', 'swipe-middle', 'swipe-last'}:
                subprocess.run(['xcrun', 'xcresulttool', 'export', '--type', 'file', '--path', bundle,
                                '--id', payload, '--output-path', str(destination / (name + '.png'))], check=True)
                exported.add(name)
            stack.extend(item.values())

if len(exported) != 3:
    raise RuntimeError(f'Expected three native swipe screenshots; got {exported}')
print('PASS exported first, middle and last native swipe boundaries')
