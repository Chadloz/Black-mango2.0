#!/usr/bin/env python3
"""Makes the line for a giveaway drop in drops/drops.json.

The code itself never goes in the repo (it's public); only its hash does. Black Mango hashes
what people paste the same way (capitals, spaces removed) and compares.

Usage:  python3 tool/giveaway_code.py MANGOGIVEAWAY thanksgiving-2026 2026-11-20 2026-11-22
        (code, pack id, first day, last day)
"""
import hashlib, json, re, sys

if len(sys.argv) != 5:
    sys.exit(__doc__)
code, pack, start, end = sys.argv[1:]
for d in (start, end):
    if not re.fullmatch(r'\d{4}-\d{2}-\d{2}', d):
        sys.exit('Dates look like 2026-11-20.')
norm = re.sub(r'\s+', '', code).upper()
h = hashlib.sha256(('black-mango-giveaway:' + norm).encode()).hexdigest()
entry = {'id': f'giveaway-{pack}-{start}', 'name': None, 'pack': pack, 'start': start, 'end': end, 'code': h}
entry.pop('name')
print('Code people paste:', norm)
print('Add this to the "drops" list in drops/drops.json:')
print('    ' + json.dumps(entry) + ',')
